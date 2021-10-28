import 'dart:typed_data';

Uint8List int32bytes(int value) {
  final r = Uint8List(4)..buffer.asInt32List()[0] = value;
  return Uint8List.fromList(r.reversed.toList());
}

Uint8List int16bytes(int value) {
  final r = Uint8List(2)..buffer.asInt16List()[0] = value;
  return Uint8List.fromList(r.reversed.toList());
}
