import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/models/room_arcore_frame.dart';

void main() {
  group('RoomArCoreFrame.fromMap', () {
    test('decodes a normal in-progress frame', () {
      final f = RoomArCoreFrame.fromMap(const {
        'tracking': true,
        'trackingFailureReason': 'NONE',
        'planesFound': true,
        'hasAnchor': false,
        'anchorTracking': false,
        'justPlaced': false,
        'reticleVisible': true,
      });
      expect(f.tracking, isTrue);
      expect(f.planesFound, isTrue);
      expect(f.hasAnchor, isFalse);
      expect(f.reticleVisible, isTrue);
      expect(f.hasTerminalError, isFalse);
    });

    test('missing keys fall back to safe defaults, never throw', () {
      final f = RoomArCoreFrame.fromMap(const {});
      expect(f.tracking, isFalse);
      expect(f.trackingFailureReason, 'NONE');
      expect(f.hasAnchor, isFalse);
      expect(f.hasTerminalError, isFalse);
      expect(f.tapRejected, isFalse);
    });

    test('decodes tapRejected — honest feedback for a genuine ARCore hit '
        'rejection (tracker §32)', () {
      final f = RoomArCoreFrame.fromMap(const {
        'tracking': true,
        'trackingFailureReason': 'NONE',
        'planesFound': true,
        'hasAnchor': false,
        'anchorTracking': false,
        'justPlaced': false,
        'reticleVisible': true,
        'tapRejected': true,
      });
      expect(f.tapRejected, isTrue);
    });

    test('a terminal state carries its message through untouched', () {
      final f = RoomArCoreFrame.fromMap(const {
        'tracking': false,
        'trackingFailureReason': 'NONE',
        'planesFound': false,
        'hasAnchor': false,
        'anchorTracking': false,
        'justPlaced': false,
        'reticleVisible': false,
        'terminalState': 'camera-permission',
        'error': 'Camera permission not granted',
      });
      expect(f.hasTerminalError, isTrue);
      expect(f.terminalState, 'camera-permission');
      expect(f.error, 'Camera permission not granted');
    });
  });

  group('guidanceMessage — honest, customer-facing copy', () {
    test('not tracking, no reason → generic scanning prompt', () {
      const f = RoomArCoreFrame(
        tracking: false,
        trackingFailureReason: 'NONE',
        planesFound: false,
        hasAnchor: false,
        anchorTracking: false,
        justPlaced: false,
        reticleVisible: false,
      );
      expect(f.guidanceMessage, contains('scanning'));
    });

    test('excessive motion failure reason → "move more slowly"', () {
      const f = RoomArCoreFrame(
        tracking: false,
        trackingFailureReason: 'EXCESSIVE_MOTION',
        planesFound: false,
        hasAnchor: false,
        anchorTracking: false,
        justPlaced: false,
        reticleVisible: false,
      );
      expect(f.guidanceMessage, contains('slowly'));
    });

    test('insufficient light → tells the customer to find a brighter area', () {
      const f = RoomArCoreFrame(
        tracking: false,
        trackingFailureReason: 'INSUFFICIENT_LIGHT',
        planesFound: false,
        hasAnchor: false,
        anchorTracking: false,
        justPlaced: false,
        reticleVisible: false,
      );
      expect(f.guidanceMessage, contains('dark'));
    });

    test('tracking, no plane yet → "move over the floor"', () {
      const f = RoomArCoreFrame(
        tracking: true,
        trackingFailureReason: 'NONE',
        planesFound: false,
        hasAnchor: false,
        anchorTracking: false,
        justPlaced: false,
        reticleVisible: false,
      );
      expect(f.guidanceMessage, contains('floor'));
    });

    test('tracking, plane found, not placed → "tap to place"', () {
      const f = RoomArCoreFrame(
        tracking: true,
        trackingFailureReason: 'NONE',
        planesFound: true,
        hasAnchor: false,
        anchorTracking: false,
        justPlaced: false,
        reticleVisible: true,
      );
      expect(f.guidanceMessage, contains('Tap'));
    });

    test('placed and anchor still tracking → placement controls hint', () {
      const f = RoomArCoreFrame(
        tracking: true,
        trackingFailureReason: 'NONE',
        planesFound: true,
        hasAnchor: true,
        anchorTracking: true,
        justPlaced: false,
        reticleVisible: false,
      );
      expect(f.guidanceMessage, contains('Drag'));
    });

    test('placed but anchor tracking lost → honest recovery message', () {
      const f = RoomArCoreFrame(
        tracking: true,
        trackingFailureReason: 'NONE',
        planesFound: true,
        hasAnchor: true,
        anchorTracking: false,
        justPlaced: false,
        reticleVisible: false,
      );
      expect(f.guidanceMessage, contains('Tracking lost'));
    });
  });
}
