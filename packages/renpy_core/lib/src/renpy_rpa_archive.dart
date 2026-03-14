import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Reader for Ren'Py RPA-3 archives.
final class RenPyRpaArchive {
  RenPyRpaArchive._(this.entries, this._bytes)
    : _entriesByLowerPath = Map.unmodifiable(
        _caseInsensitiveIndex(entries.keys),
      );

  factory RenPyRpaArchive(Uint8List bytes) {
    final newline = bytes.indexOf(0x0a);
    if (newline == -1) {
      throw const FormatException('RPA archive header is missing');
    }

    final header = ascii.decode(bytes.sublist(0, newline));
    final match = RegExp(
      r'^RPA-3\.0\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)$',
    ).firstMatch(header);
    if (match == null) {
      throw FormatException('Unsupported RPA archive header: $header');
    }

    final indexOffset = int.parse(match.group(1)!, radix: 16);
    final key = int.parse(match.group(2)!, radix: 16);
    final compressedIndex = bytes.sublist(indexOffset);
    final indexBytes = Uint8List.fromList(
      ZLibDecoder().decodeBytes(compressedIndex),
    );

    return RenPyRpaArchive._(_RpaIndexParser(indexBytes, key).parse(), bytes);
  }

  final Map<String, RenPyRpaEntry> entries;
  final Uint8List _bytes;
  final Map<String, String> _entriesByLowerPath;

  Uint8List? read(String path) {
    final normalized = _normalizeArchivePath(path);
    final entry =
        entries[normalized] ??
        entries[_entriesByLowerPath[normalized.toLowerCase()]];
    if (entry == null) return null;
    return Uint8List.sublistView(
      _bytes,
      entry.offset,
      entry.offset + entry.length,
    );
  }
}

String _normalizeArchivePath(String path) {
  return path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^/+'), '');
}

Map<String, String> _caseInsensitiveIndex(Iterable<String> paths) {
  final index = <String, String>{};
  for (final path in paths) {
    index.putIfAbsent(_normalizeArchivePath(path).toLowerCase(), () => path);
  }
  return index;
}

final class RenPyRpaEntry {
  const RenPyRpaEntry({required this.offset, required this.length});

  final int offset;
  final int length;
}

final class _RpaIndexParser {
  _RpaIndexParser(this.bytes, this.key);

  final Uint8List bytes;
  final int key;
  int _position = 0;

  Map<String, RenPyRpaEntry> parse() {
    final entries = <String, RenPyRpaEntry>{};
    _expect(0x80); // PROTO
    _position++; // Protocol version.
    _expect(0x7d); // EMPTY_DICT
    _skipMemo();
    _expect(0x28); // MARK

    while (_peek() != 0x75) {
      final path = _readString();
      _skipMemo();
      _expect(0x5d); // EMPTY_LIST
      _skipMemo();
      final offset = _readInteger() ^ key;
      final length = _readInteger() ^ key;
      _readString(); // Archive prefix, unused by FiestaVN for now.
      _expect(0x87); // TUPLE3
      _skipMemo();
      _expect(0x61); // APPEND
      entries[path] = RenPyRpaEntry(offset: offset, length: length);
    }

    _expect(0x75); // SETITEMS
    _expect(0x2e); // STOP
    return entries;
  }

  int _peek() => bytes[_position];

  void _expect(int opcode) {
    final actual = bytes[_position++];
    if (actual != opcode) {
      throw FormatException(
        'Unsupported RPA index opcode 0x${actual.toRadixString(16)} at '
        '${_position - 1}; expected 0x${opcode.toRadixString(16)}',
      );
    }
  }

  void _skipMemo() {
    final opcode = bytes[_position];
    if (opcode == 0x71) {
      _position += 2; // BINPUT + one-byte memo index.
    } else if (opcode == 0x72) {
      _position += 5; // LONG_BINPUT + four-byte memo index.
    }
  }

  String _readString() {
    final opcode = bytes[_position++];
    switch (opcode) {
      case 0x58: // BINUNICODE
        final length = _readUint32();
        return utf8.decode(bytes.sublist(_position, _position += length));
      case 0x55: // SHORT_BINSTRING
        final length = bytes[_position++];
        return latin1.decode(bytes.sublist(_position, _position += length));
      default:
        throw FormatException(
          'Unsupported RPA index string opcode 0x${opcode.toRadixString(16)}',
        );
    }
  }

  int _readInteger() {
    final opcode = bytes[_position++];
    switch (opcode) {
      case 0x4a: // BININT
        return _readInt32();
      case 0x8a: // LONG1
        final length = bytes[_position++];
        final raw = bytes.sublist(_position, _position += length);
        var value = 0;
        for (var i = 0; i < raw.length; i += 1) {
          value |= raw[i] << (8 * i);
        }
        return value;
      default:
        throw FormatException(
          'Unsupported RPA index integer opcode 0x${opcode.toRadixString(16)}',
        );
    }
  }

  int _readUint32() {
    final value =
        bytes[_position] |
        (bytes[_position + 1] << 8) |
        (bytes[_position + 2] << 16) |
        (bytes[_position + 3] << 24);
    _position += 4;
    return value;
  }

  int _readInt32() {
    final value = _readUint32();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }
}
