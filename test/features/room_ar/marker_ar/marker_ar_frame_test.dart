import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_frame.dart';

void main() {
  group('MarkerArFrame.fromMap — tracking-state mapping', () {
    MarkerArFrame frame(Map<String, dynamic> m) => MarkerArFrame.fromMap(m);

    test('maps each native track string to the honest enum', () {
      expect(frame({'track': 'tracking'}).track, MarkerTrackState.tracking);
      expect(frame({'track': 'holding'}).track, MarkerTrackState.holding);
      expect(frame({'track': 'toofar'}).track, MarkerTrackState.tooFar);
      expect(frame({'track': 'searching'}).track, MarkerTrackState.searching);
      expect(frame({}).track, MarkerTrackState.searching); // default
      expect(frame({'track': 'weird'}).track, MarkerTrackState.searching);
    });

    test('maps the legacy coarse state', () {
      expect(frame({'state': 'detected'}).status, MarkerArStatus.detected);
      expect(
        frame({'state': 'error', 'message': 'boom'}).status,
        MarkerArStatus.error,
      );
      expect(frame({'state': 'error', 'message': 'boom'}).message, 'boom');
      expect(frame({'state': 'searching'}).status, MarkerArStatus.searching);
    });

    test('extracts a pose only when both R and t are present', () {
      final withPose = frame({
        'track': 'tracking',
        'R': [1, 0, 0, 0, 1, 0, 0, 0, 1],
        't': [0.1, 0.2, 1.3],
        'K': [1000.0, 1000.0, 360.0, 640.0],
        'imgW': 720,
        'imgH': 1280,
        'distM': 1.3,
      });
      expect(withPose.pose, isNotNull);
      expect(withPose.pose!.t, [0.1, 0.2, 1.3]);
      expect(withPose.hasIntrinsics, isTrue);

      final noPose = frame({'track': 'holding', 'heldMs': 400.0});
      expect(noPose.pose, isNull);
      expect(noPose.heldMs, 400.0);
      expect(noPose.hasIntrinsics, isFalse);
    });

    test('carries metrics through unchanged', () {
      final f = frame({
        'track': 'tracking',
        'fps': 19.5,
        'detMs': 41.0,
        'pass': 'roi',
        'markerSidePx': 108.0,
        'markerSizeMm': 160.0,
        'focalMm': 3.6,
      });
      expect(f.fps, 19.5);
      expect(f.detMs, 41.0);
      expect(f.pass, 'roi');
      expect(f.markerSidePx, 108.0);
    });
  });
}
