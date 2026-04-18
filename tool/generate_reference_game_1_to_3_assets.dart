import 'dart:io';
import 'dart:typed_data';

void main() {
  final assets = <_SolidPngAsset>[
    _SolidPngAsset(
      'apps/renfly/assets/games/1/game/images/whitehouse.jpg',
      800,
      600,
      const _Rgba(32, 72, 128),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/1/game/images/eileen_happy.png',
      220,
      520,
      const _Rgba(232, 64, 80),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/1/game/images/eileen_upset.png',
      220,
      520,
      const _Rgba(184, 32, 112),
    ),
    for (final name in ['S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'LR5'])
      _SolidPngAsset(
        'apps/renfly/assets/games/2/game/images/$name.png',
        800,
        600,
        _game2Color(name),
      ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/mainmenu.jpg',
      800,
      600,
      const _Rgba(24, 48, 96),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/gamemenu.jpg',
      800,
      600,
      const _Rgba(48, 24, 96),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/frame.png',
      320,
      96,
      const _Rgba(16, 16, 16, 220),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/button.png',
      260,
      64,
      const _Rgba(40, 88, 160),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/button_checked.png',
      260,
      64,
      const _Rgba(64, 132, 200),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/carillon.jpg',
      800,
      600,
      const _Rgba(32, 96, 96),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/whitehouse.jpg',
      800,
      600,
      const _Rgba(40, 72, 128),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/washington.jpg',
      800,
      600,
      const _Rgba(64, 96, 144),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/9a_happy.png',
      220,
      520,
      const _Rgba(232, 64, 80),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/9a_vhappy.png',
      220,
      520,
      const _Rgba(255, 96, 96),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/9a_concerned.png',
      220,
      520,
      const _Rgba(184, 32, 112),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/ground.png',
      800,
      600,
      const _Rgba(24, 88, 56),
    ),
    _SolidPngAsset(
      'apps/renfly/assets/games/3/game/images/selected.png',
      800,
      600,
      const _Rgba(48, 128, 80),
    ),
  ];

  for (final asset in assets) {
    asset.write();
  }

  File('apps/renfly/assets/games/3/game/sun-flower-slow-drag.mid')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(_emptyMidi());
}

_Rgba _game2Color(String name) {
  return switch (name) {
    'S2' => const _Rgba(28, 52, 92),
    'S3' => const _Rgba(48, 72, 112),
    'S4' => const _Rgba(68, 92, 132),
    'S5' => const _Rgba(88, 112, 152),
    'S6' => const _Rgba(128, 48, 72),
    'S7' => const _Rgba(152, 64, 88),
    'LR5' => const _Rgba(72, 96, 48),
    _ => const _Rgba(96, 96, 96),
  };
}

final class _SolidPngAsset {
  const _SolidPngAsset(this.path, this.width, this.height, this.color);

  final String path;
  final int width;
  final int height;
  final _Rgba color;

  void write() {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_solidPng(width, height, color));
  }
}

final class _Rgba {
  const _Rgba(this.red, this.green, this.blue, [this.alpha = 255]);

  final int red;
  final int green;
  final int blue;
  final int alpha;
}

List<int> _solidPng(int width, int height, _Rgba color) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y += 1) {
    raw.addByte(0);
    for (var x = 0; x < width; x += 1) {
      raw
        ..addByte(color.red)
        ..addByte(color.green)
        ..addByte(color.blue)
        ..addByte(color.alpha);
    }
  }

  return [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ..._chunk('IHDR', _uint32(width) + _uint32(height) + [8, 6, 0, 0, 0]),
    ..._chunk('IDAT', ZLibEncoder().convert(raw.takeBytes())),
    ..._chunk('IEND', const []),
  ];
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final crcInput = [...typeBytes, ...data];
  return [
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32(crcInput)),
  ];
}

List<int> _uint32(int value) {
  return [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i += 1) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

List<int> _emptyMidi() {
  return [
    // Header chunk: format 0, one track, 96 ticks per quarter note.
    0x4d,
    0x54,
    0x68,
    0x64,
    0x00,
    0x00,
    0x00,
    0x06,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x60,
    // Track chunk: immediate end-of-track meta event.
    0x4d,
    0x54,
    0x72,
    0x6b,
    0x00,
    0x00,
    0x00,
    0x04,
    0x00,
    0xff,
    0x2f,
    0x00,
  ];
}
