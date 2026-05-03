import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('RenPyRpaArchive.decodeLong1', () {
    test('decodes a positive little-endian value', () {
      // 0x0102 little-endian, high bit clear.
      expect(RenPyRpaArchive.decodeLong1(const [0x02, 0x01]), 0x0102);
    });

    test('sign-extends a single-byte negative value', () {
      // 0xFD is -3 in two's complement.
      expect(RenPyRpaArchive.decodeLong1(const [0xfd]), -3);
    });

    test('sign-extends a multi-byte negative value', () {
      // 0xFF 0xFF -> -1; 0x00 0xFF -> -256.
      expect(RenPyRpaArchive.decodeLong1(const [0xff, 0xff]), -1);
      expect(RenPyRpaArchive.decodeLong1(const [0x00, 0xff]), -256);
    });

    test('treats a trailing zero byte as a positive value', () {
      // 0x80 0x00 keeps the high bit clear in the top byte, so it stays +128.
      expect(RenPyRpaArchive.decodeLong1(const [0x80, 0x00]), 128);
    });

    test('decodes an empty payload as zero', () {
      expect(RenPyRpaArchive.decodeLong1(const []), 0);
    });
  });

  group('RenPyRpaArchive index decoding', () {
    test('decodes SHORT_BINSTRING paths using the archive encoding', () {
      // 'caf\u{00E9}.rpy' encodes to non-latin1 multibyte UTF-8; a latin1 decode would
      // mangle the path so the lookup would fail.
      const key = 0x42424242;
      const data = <int>[9, 8, 7];
      const path = 'caf\u{00E9}.rpy';
      const headerLength = 34;
      const offset = headerLength;
      final length = data.length;

      final index = _pickleIndex(
        path: _shortBinString(utf8.encode(path)),
        offsetField: _binInt(offset ^ key),
        lengthField: _binInt(length ^ key),
        prefixField: _shortBinString(const []),
      );

      final archive = _buildArchive(
        key: key,
        payload: data,
        index: index,
        indexOffset: headerLength + data.length,
      );

      final reader = RenPyRpaArchive(archive);
      expect(reader.read(path), data);
    });
  });
}

Uint8List _buildArchive({
  required int key,
  required List<int> payload,
  required List<int> index,
  required int indexOffset,
}) {
  final compressedIndex = ZLibEncoder().encode(index);
  final header =
      'RPA-3.0 ${indexOffset.toRadixString(16).padLeft(16, '0')} '
      '${key.toRadixString(16).padLeft(8, '0')}\n';
  return Uint8List.fromList([
    ...ascii.encode(header),
    ...payload,
    ...compressedIndex,
  ]);
}

List<int> _pickleIndex({
  required List<int> path,
  required List<int> offsetField,
  required List<int> lengthField,
  required List<int> prefixField,
}) {
  final bytes = BytesBuilder()..add([0x80, 0x02, 0x7d, 0x71, 0x01, 0x28]);
  bytes
    ..add(path)
    ..add([0x5d, 0x71, 0x02])
    ..add(offsetField)
    ..add(lengthField)
    ..add(prefixField)
    ..add([0x87, 0x71, 0x03, 0x61, 0x75, 0x2e]);
  return bytes.toBytes();
}

List<int> _shortBinString(List<int> value) {
  return [0x55, value.length, ...value];
}

List<int> _binInt(int value) => [0x4a, ..._uint32(value)];

List<int> _uint32(int value) {
  return [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}
