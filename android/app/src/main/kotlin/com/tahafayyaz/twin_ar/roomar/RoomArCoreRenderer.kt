package com.tahafayyaz.twin_ar.roomar

import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.util.Log
import android.view.MotionEvent
import android.view.Surface
import android.view.WindowManager
import com.google.ar.core.Anchor
import com.google.ar.core.Camera
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.ArrayBlockingQueue
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * TWin AR — Phase 9.2 R6 Tier-1 markerless-ARCore GL layer.
 *
 * Owns exactly the parts of an ARCore session that must run on the GL thread
 * that holds the camera's external texture: the per-frame `session.update()`
 * call, drawing the real camera passthrough, drawing a lightweight outline
 * over every detected horizontal surface (floor **and** table-height
 * surfaces — both report as `Plane.Type.HORIZONTAL_UPWARD_FACING`), a small
 * placement reticle that live-previews where a tap would land, and doing the
 * actual `frame.hitTest` + `Anchor` creation for a queued tap.
 *
 * Does **not** own [Session] construction/resume/pause/close — those are
 * main-thread operations owned by [RoomArCoreView] (ARCore's own contract),
 * which hands this renderer the [Session] once it is ready. Does not render
 * the product model at all — [RoomArCoreModelRenderer] (transparent Filament
 * `TextureView`, layered on top) does that, driven by [Listener.onCameraPose]
 * + [currentAnchor].
 */
class RoomArCoreRenderer(
    private val context: Context,
    private val listener: Listener,
) : GLSurfaceView.Renderer {

    interface Listener {
        /** Always called on the GL thread — the caller must post to the main
         *  thread before touching Flutter state from it. [anchorPoseMatrix] is
         *  the placed anchor's world-space column-major 4x4 transform, or
         *  `null` when nothing is placed — passed directly (rather than via a
         *  getter back onto this renderer) so callers never need a reference
         *  to the renderer instance from inside its own constructor.
         *  [initialYawDegrees] is non-null exactly on the frame a *new*
         *  placement (not a reposition) happens — see [faceCameraYawDegrees]. */
        fun onFrame(
            state: RoomArCoreFrameState,
            anchorPoseMatrix: FloatArray?,
            initialYawDegrees: Float? = null,
        )

        /** The camera's live view + projection matrices this frame
         *  (column-major, OpenGL convention, exactly `Camera.getViewMatrix`/
         *  `getProjectionMatrix`'s own output) — only meaningful while
         *  tracking. */
        fun onCameraPose(viewMatrix: FloatArray, projectionMatrix: FloatArray)
    }

    private val tag = "RoomArCoreRenderer"

    @Volatile var session: Session? = null

    // ── camera passthrough ──────────────────────────────────────────────────
    private var backgroundTextureId = -1
    private var bgProgram = 0
    private var bgPosAttrib = 0
    private var bgTexAttrib = 0
    private var bgTexUniform = 0
    private val quadCoords = floatArrayOf(-1f, -1f, +1f, -1f, -1f, +1f, +1f, +1f)
    private var quadTexCoords = floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f)
    private var quadCoordsBuf = toFloatBuffer(quadCoords)
    private var quadTexCoordsBuf = toFloatBuffer(quadTexCoords)

    // ── flat-color program (plane outlines + reticle) ───────────────────────
    private var colorProgram = 0
    private var colorPosAttrib = 0
    private var colorMvpUniform = 0
    private var colorColorUniform = 0
    // unit square outline, local XZ plane (y = 0): corners at (±1, 0, ±1) —
    // used only for the small placement reticle. Detected-plane outlines are
    // drawn from each plane's own real polygon (see drawPlanes), not this
    // fixed shape — see that method's doc comment for why the distinction
    // matters for tap accuracy.
    private val unitSquareOutline = floatArrayOf(
        -1f, 0f, -1f, 1f, 0f, -1f, 1f, 0f, 1f, -1f, 0f, 1f,
    )
    private val unitSquareOutlineBuf = toFloatBuffer(unitSquareOutline)

    // ── tap queue: main thread enqueues, GL thread consumes at most one/frame.
    // The same op handles BOTH "place a new anchor" (nothing placed yet) and
    // "reposition" (an anchor already exists — ARCore anchors are pose-
    // immutable, so "moving" one means detach + recreate at the fresh hit).
    private val tapQueue = ArrayBlockingQueue<MotionEvent>(1)

    @Volatile var viewportWidth = 1
        private set
    @Volatile var viewportHeight = 1
        private set

    /** Set by [RoomArCoreView] while a reposition drag is in progress, so the
     *  live reticle keeps showing where the object would land even though one
     *  is already placed. */
    @Volatile var dragging = false

    @Volatile private var placedAnchor: Anchor? = null

    fun queueTap(x: Float, y: Float) {
        tapQueue.poll()?.recycle()
        tapQueue.offer(MotionEvent.obtain(0, 0, MotionEvent.ACTION_UP, x, y, 0))
    }

    /** Removes any placed anchor (customer tapped "Remove" / "Reset"). Safe to
     *  call from any thread — [Anchor.detach] is itself thread-safe. */
    fun clearAnchor() {
        placedAnchor?.detach()
        placedAnchor = null
    }

    fun currentAnchor(): Anchor? = placedAnchor

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 0f)
        backgroundTextureId = createExternalTexture()
        bgProgram = createProgram(BG_VERTEX_SHADER, BG_FRAGMENT_SHADER)
        bgPosAttrib = GLES20.glGetAttribLocation(bgProgram, "a_Position")
        bgTexAttrib = GLES20.glGetAttribLocation(bgProgram, "a_TexCoord")
        bgTexUniform = GLES20.glGetUniformLocation(bgProgram, "u_Texture")

        colorProgram = createProgram(COLOR_VERTEX_SHADER, COLOR_FRAGMENT_SHADER)
        colorPosAttrib = GLES20.glGetAttribLocation(colorProgram, "a_Position")
        colorMvpUniform = GLES20.glGetUniformLocation(colorProgram, "u_MVP")
        colorColorUniform = GLES20.glGetUniformLocation(colorProgram, "u_Color")

        session?.setCameraTextureName(backgroundTextureId)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        viewportWidth = width.coerceAtLeast(1)
        viewportHeight = height.coerceAtLeast(1)
        session?.setDisplayGeometry(displayRotation(), width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val session = this.session ?: return
        try {
            session.setCameraTextureName(backgroundTextureId)
            val frame: Frame = session.update()
            val camera: Camera = frame.camera

            if (frame.hasDisplayGeometryChanged()) {
                frame.transformCoordinates2d(
                    Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                    quadCoords,
                    Coordinates2d.TEXTURE_NORMALIZED,
                    quadTexCoords,
                )
                quadTexCoordsBuf = toFloatBuffer(quadTexCoords)
            }

            drawBackground()

            val tracking = camera.trackingState == TrackingState.TRACKING
            var reticleVisible = false
            var justPlaced = false
            var initialYawDegrees: Float? = null
            var tapRejected = false

            if (tracking) {
                val viewMatrix = FloatArray(16)
                val projMatrix = FloatArray(16)
                camera.getViewMatrix(viewMatrix, 0)
                camera.getProjectionMatrix(projMatrix, 0, 0.05f, 30f)
                listener.onCameraPose(viewMatrix, projMatrix)

                val vp = FloatArray(16)
                Matrix.multiplyMM(vp, 0, projMatrix, 0, viewMatrix, 0)
                val planes = session.getAllTrackables(Plane::class.java)
                drawPlanes(planes, vp)

                // The reticle previews where a tap would land: always before
                // anything is placed, and while the customer is actively
                // dragging an already-placed object to reposition it.
                if (placedAnchor == null || dragging) {
                    val centerHit = validHit(
                        frame.hitTest(viewportWidth / 2f, viewportHeight / 2f),
                    )
                    if (centerHit != null) {
                        reticleVisible = true
                        drawReticle(centerHit.hitPose.toMatrixArray(), vp)
                    }
                }

                // One hit-test per frame at most, from THIS frame's own
                // `update()` — never a second, out-of-band `update()` call.
                // Handles both "place" (nothing placed yet) and "reposition"
                // (replace the existing anchor at the fresh hit) identically.
                val tap = tapQueue.poll()
                if (tap != null) {
                    val rawHits = frame.hitTest(tap)
                    val hit = validHit(rawHits)
                    if (hit != null) {
                        val wasPlaced = placedAnchor != null
                        placedAnchor?.detach()
                        placedAnchor = hit.createAnchor()
                        justPlaced = !wasPlaced
                        if (justPlaced) {
                            initialYawDegrees = faceCameraYawDegrees(camera, hit.hitPose)
                        }
                    } else if (placedAnchor == null) {
                        // Honest visible feedback for a genuine *initial*-
                        // placement miss — not raised for a reposition-drag
                        // sample landing briefly on an unmapped spot mid-drag
                        // (self-evident from the object simply not following
                        // there, and would otherwise spam a flash message on
                        // every such sample during an ordinary drag).
                        tapRejected = true
                    }
                    tap.recycle()
                }
            } else {
                tapQueue.poll()?.recycle()
            }

            val anyPlanesFound = tracking && session.getAllTrackables(Plane::class.java)
                .any { it.trackingState == TrackingState.TRACKING && it.subsumedBy == null }

            listener.onFrame(
                RoomArCoreFrameState(
                    tracking = tracking,
                    trackingFailureReason = RoomArCoreFrameState.failureReasonName(camera),
                    planesFound = anyPlanesFound,
                    hasAnchor = placedAnchor != null,
                    anchorTracking = placedAnchor?.trackingState == TrackingState.TRACKING,
                    justPlaced = justPlaced,
                    reticleVisible = reticleVisible,
                    tapRejected = tapRejected,
                ),
                placedAnchor?.pose?.toMatrixArray(),
                initialYawDegrees,
            )
        } catch (e: CameraNotAvailableException) {
            Log.e(tag, "camera unavailable", e)
            listener.onFrame(RoomArCoreFrameState.cameraUnavailable(), null, null)
        } catch (t: Throwable) {
            Log.e(tag, "draw frame error", t)
            listener.onFrame(RoomArCoreFrameState.error(t.message ?: "AR render error"), null, null)
        }
    }

    /**
     * The Y-axis yaw (degrees) that rotates the model's authored front axis
     * (local -Z, per `SCALE_CONTRACT.md`) to face [camera] from [anchorPose].
     *
     * Phase 9.2 R6 physical smoke-test finding #8 (tracker §30): the model
     * finally placed reliably (§27/§29), and only then did it become visible
     * that it can place facing backward — [anchorPose] (from ARCore's own
     * `hitTest`) has no defined in-plane rotation the app can rely on; it
     * reflects however ARCore happened to establish that plane's local frame
     * when first mapped, with zero relation to where the camera is. Nothing
     * previously computed a sensible initial facing, so the model inherited
     * that arbitrary rotation directly. Computed once, at the exact moment of
     * *initial* placement only (never on a reposition-drag, which must
     * preserve whatever yaw the customer already dialled in): the direction
     * from the anchor to the camera, projected onto the horizontal (X/Z)
     * plane, standing in for "face the viewer" — deliberately **not** derived
     * from [anchorPose]'s own rotation at all, so it can't inherit that
     * arbitrariness.
     */
    private fun faceCameraYawDegrees(camera: Camera, anchorPose: com.google.ar.core.Pose): Float {
        val dx = camera.pose.tx() - anchorPose.tx()
        val dz = camera.pose.tz() - anchorPose.tz()
        // Local -Z (0,0,-1) rotated by Matrix.setRotateM(_, _, deg, 0,1,0)
        // maps to world (-sin(deg), 0, -cos(deg)) — solve for the angle that
        // makes that equal the normalized (dx, dz) direction to the camera.
        return Math.toDegrees(kotlin.math.atan2(-dx, -dz).toDouble()).toFloat()
    }

    /** Only a genuine, real-surface hit counts: a horizontal, upward-facing
     *  plane (covers both floors and table-height surfaces) whose polygon
     *  actually contains the hit point, OR — the standard ARCore fallback for
     *  a plane whose polygon hasn't grown to cover a valid point yet — a
     *  feature `Point` whose estimated surface normal is close enough to
     *  vertical (dot with world-up > 0.85, i.e. within ~32° of horizontal) to
     *  still honestly count as "a horizontal surface". Never accepts a
     *  vertical surface or an un-oriented point. */
    private fun validHit(hits: List<HitResult>): HitResult? {
        for (hit in hits) {
            val trackable = hit.trackable
            if (trackable is Plane &&
                trackable.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                trackable.trackingState == TrackingState.TRACKING &&
                trackable.isPoseInPolygon(hit.hitPose)
            ) {
                return hit
            }
            if (trackable is com.google.ar.core.Point &&
                trackable.orientationMode ==
                    com.google.ar.core.Point.OrientationMode.ESTIMATED_SURFACE_NORMAL
            ) {
                val m = hit.hitPose.toMatrixArray()
                val upY = m[9] // column-major: column 1 (Y axis) . Y component
                if (upY > 0.85f) return hit
            }
        }
        return null
    }

    // ── drawing ──────────────────────────────────────────────────────────────

    private fun drawBackground() {
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glUseProgram(bgProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, backgroundTextureId)
        GLES20.glUniform1i(bgTexUniform, 0)
        quadCoordsBuf.position(0)
        GLES20.glVertexAttribPointer(bgPosAttrib, 2, GLES20.GL_FLOAT, false, 0, quadCoordsBuf)
        GLES20.glEnableVertexAttribArray(bgPosAttrib)
        quadTexCoordsBuf.position(0)
        GLES20.glVertexAttribPointer(bgTexAttrib, 2, GLES20.GL_FLOAT, false, 0, quadTexCoordsBuf)
        GLES20.glEnableVertexAttribArray(bgTexAttrib)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(bgPosAttrib)
        GLES20.glDisableVertexAttribArray(bgTexAttrib)
        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    /**
     * Draws each detected plane's **real polygon** — not `extentX`/`extentZ`'s
     * bounding-rectangle approximation, which was the previous behaviour.
     *
     * Phase 9.2 R6 physical smoke-test finding #5 (tracker §28): once touch
     * delivery itself was fixed (§27), `tapsSent` still climbed to several
     * attempts before an anchor placed, on every product tested. ARCore's own
     * acceptance test for a tap — `Plane.isPoseInPolygon` (used by
     * [validHit]) — checks the plane's actual, incrementally-mapped polygon,
     * which is very often smaller and less regular than its bounding box,
     * especially soon after a surface is first found. Drawing the bounding
     * box as "the highlighted area to tap" therefore invited taps the real
     * hit-test would legitimately reject — a mismatch between what the
     * customer is shown and what is actually accepted, not a gesture or
     * touch-delivery defect. Drawing the true polygon instead makes the
     * visible guide match the real accepted region exactly.
     */
    private fun drawPlanes(planes: Collection<Plane>, vp: FloatArray) {
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUseProgram(colorProgram)
        for (plane in planes) {
            if (plane.trackingState != TrackingState.TRACKING) continue
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            if (plane.subsumedBy != null) continue
            // A fresh, already-rewound FloatBuffer of (x, z) pairs in the
            // plane's own local coordinate frame — a new instance every call,
            // per the ARCore API contract.
            val polygon = plane.polygon
            val vertexCount = polygon.remaining() / 2
            if (vertexCount < 3) continue // not enough to draw yet
            val verts = FloatArray(vertexCount * 3)
            var i = 0
            while (polygon.remaining() >= 2) {
                verts[i * 3] = polygon.get()
                verts[i * 3 + 1] = 0f
                verts[i * 3 + 2] = polygon.get()
                i++
            }
            val mvp = FloatArray(16)
            Matrix.multiplyMM(mvp, 0, vp, 0, plane.centerPose.toMatrixArray(), 0)
            drawColoredLineLoop(
                toFloatBuffer(verts), vertexCount, mvp, floatArrayOf(1f, 1f, 1f, 0.55f),
            )
        }
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun drawReticle(hitPoseMatrix: FloatArray, vp: FloatArray) {
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUseProgram(colorProgram)
        val scaled = FloatArray(16)
        Matrix.scaleM(scaled, 0, hitPoseMatrix, 0, 0.09f, 1f, 0.09f)
        val mvp = FloatArray(16)
        Matrix.multiplyMM(mvp, 0, vp, 0, scaled, 0)
        drawColoredLineLoop(unitSquareOutlineBuf, 4, mvp, floatArrayOf(1f, 1f, 1f, 0.9f))
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun drawColoredLineLoop(
        buf: FloatBuffer, count: Int, mvp: FloatArray, color: FloatArray,
    ) {
        GLES20.glLineWidth(4f)
        buf.position(0)
        GLES20.glVertexAttribPointer(colorPosAttrib, 3, GLES20.GL_FLOAT, false, 0, buf)
        GLES20.glEnableVertexAttribArray(colorPosAttrib)
        GLES20.glUniformMatrix4fv(colorMvpUniform, 1, false, mvp, 0)
        GLES20.glUniform4fv(colorColorUniform, 1, color, 0)
        GLES20.glDrawArrays(GLES20.GL_LINE_LOOP, 0, count)
        GLES20.glDisableVertexAttribArray(colorPosAttrib)
    }

    private fun createExternalTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val id = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, id)
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE,
        )
        return id
    }

    private fun displayRotation(): Int {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        return wm?.defaultDisplay?.rotation ?: Surface.ROTATION_0
    }

    companion object {
        private const val BG_VERTEX_SHADER = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
              gl_Position = a_Position;
              v_TexCoord = a_TexCoord;
            }
        """

        private const val BG_FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() {
              gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """

        private const val COLOR_VERTEX_SHADER = """
            uniform mat4 u_MVP;
            attribute vec4 a_Position;
            void main() { gl_Position = u_MVP * a_Position; }
        """

        private const val COLOR_FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Color;
            void main() { gl_FragColor = u_Color; }
        """

        private fun loadShader(type: Int, src: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, src)
            GLES20.glCompileShader(shader)
            return shader
        }

        private fun createProgram(vs: String, fs: String): Int {
            val v = loadShader(GLES20.GL_VERTEX_SHADER, vs)
            val f = loadShader(GLES20.GL_FRAGMENT_SHADER, fs)
            val p = GLES20.glCreateProgram()
            GLES20.glAttachShader(p, v)
            GLES20.glAttachShader(p, f)
            GLES20.glLinkProgram(p)
            return p
        }

        private fun toFloatBuffer(data: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder())
                .asFloatBuffer().apply { put(data); position(0) }
    }
}

/** Column-major 4x4 transform matrix for this pose (ARCore/OpenGL convention). */
private fun com.google.ar.core.Pose.toMatrixArray(): FloatArray {
    val m = FloatArray(16)
    toMatrix(m, 0)
    return m
}
