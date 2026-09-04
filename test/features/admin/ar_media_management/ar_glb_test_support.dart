import 'dart:io';

import 'package:twin_ar/features/admin/ar_media_management/services/ar_model_file_picker.dart';

import '../../room_ar/model_delivery/glb_test_support.dart';

/// Writes a structurally valid, floor-centred box `.glb` of the given real
/// metres to a temp file and returns it. Reuses the model-delivery test GLB
/// builder so admin-side validation is exercised against the same bytes
/// `GlbInspector` / `RoomArModelService` validate.
File writeBoxGlb({
  required Directory dir,
  required String name,
  double x = 0.70,
  double y = 0.82,
  double z = 0.72,
  double minY = 0,
}) {
  final bytes = buildGlb(boxGltf(x: x, y: y, z: z, minY: minY));
  return File('${dir.path}/$name')..writeAsBytesSync(bytes);
}

/// Non-GLB junk, for the "reject a non-model file" path.
File writeJunkFile(Directory dir, String name) =>
    File('${dir.path}/$name')..writeAsBytesSync(List<int>.filled(64, 7));

/// A fake picker returning a pre-seeded file (or `null` = admin cancelled),
/// so the ViewModel's pick→validate→stage path is testable with no platform
/// channel.
class FakeArModelFilePicker implements ArModelFilePicker {
  FakeArModelFilePicker([this.next]);

  File? next;
  Object? throwOnPick;
  int pickCount = 0;

  @override
  Future<File?> pickGlb() async {
    pickCount++;
    if (throwOnPick != null) throw throwOnPick!;
    return next;
  }
}
