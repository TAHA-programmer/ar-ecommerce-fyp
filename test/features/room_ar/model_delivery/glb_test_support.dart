import 'dart:convert';
import 'dart:typed_data';

/// Builds a minimal but structurally valid `.glb` (glTF 2.0 binary) container
/// for tests: 12-byte header + JSON chunk (+ optional BIN chunk), each chunk
/// 4-byte aligned per the GLB spec. The [gltf] map is serialised as-is, so a
/// test can craft exactly the scene graph / accessor bounds it wants.
Uint8List buildGlb(Map<String, dynamic> gltf, {Uint8List? bin}) {
  final jsonBytes = utf8.encode(json.encode(gltf));
  final jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  final jsonChunkLen = jsonBytes.length + jsonPad;

  var binChunkLen = 0;
  Uint8List? binPadded;
  if (bin != null) {
    final binPad = (4 - (bin.length % 4)) % 4;
    binChunkLen = bin.length + binPad;
    binPadded = Uint8List(binChunkLen)..setRange(0, bin.length, bin);
  }

  final total = 12 + 8 + jsonChunkLen + (bin != null ? 8 + binChunkLen : 0);

  final out = BytesBuilder();
  final header = ByteData(12);
  header.setUint32(0, 0x46546C67, Endian.little); // "glTF"
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, total, Endian.little);
  out.add(header.buffer.asUint8List());

  final jsonHeader = ByteData(8);
  jsonHeader.setUint32(0, jsonChunkLen, Endian.little);
  jsonHeader.setUint32(4, 0x4E4F534A, Endian.little); // "JSON"
  out.add(jsonHeader.buffer.asUint8List());
  out.add(jsonBytes);
  out.add(Uint8List(jsonPad)..fillRange(0, jsonPad, 0x20)); // space padding

  if (bin != null) {
    final binHeader = ByteData(8);
    binHeader.setUint32(0, binChunkLen, Endian.little);
    binHeader.setUint32(4, 0x004E4942, Endian.little); // "BIN\0"
    out.add(binHeader.buffer.asUint8List());
    out.add(binPadded!);
  }

  return out.toBytes();
}

/// A one-node, one-mesh glTF whose single `POSITION` accessor spans
/// `[-x/2 .. x/2] × [0 .. y] × [-z/2 .. z/2]` metres — i.e. a floor-centred box
/// of `(width X, height Y, depth Z)`.
Map<String, dynamic> boxGltf({
  required double x,
  required double y,
  required double z,
  double minY = 0,
  Map<String, dynamic>? nodeExtra,
}) => {
  'asset': {'version': '2.0'},
  'scene': 0,
  'scenes': [
    {
      'nodes': [0],
    },
  ],
  'nodes': [
    {'mesh': 0, ...?nodeExtra},
  ],
  'meshes': [
    {
      'primitives': [
        {
          'attributes': {'POSITION': 0},
        },
      ],
    },
  ],
  'accessors': [
    {
      'type': 'VEC3',
      'componentType': 5126,
      'count': 8,
      'min': [-x / 2, minY, -z / 2],
      'max': [x / 2, minY + y, z / 2],
    },
  ],
};
