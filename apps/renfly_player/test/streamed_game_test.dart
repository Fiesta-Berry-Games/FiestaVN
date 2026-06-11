import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:renfly_player/streamed_game.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/renpy_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://example.test/games/demo';

const _script = '''
label start:
    scene bg room
    play music "illurock.opus"
    show eileen happy
    e "Streamed hello."
''';

const _imagePaths = [
  'game/images/bg room.png',
  'game/images/eileen happy.png',
];
const _audioPath = 'game/illurock.opus';

/// A valid 1x1 transparent PNG so MemoryImage sprites decode cleanly.
final Uint8List _pngBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);
final Uint8List _opusBytes = Uint8List.fromList(List<int>.filled(64, 7));

int get _gateTotalBytes => _pngBytes.length * 2 + _opusBytes.length;

String _flyScript() {
  final parsed = RenPyParser().parse(_script, 'script.rpy').script;
  return const FlyCodec().encodeToString(parsed);
}

/// Serves the manifest, script, and asset bytes. Asset responses listed in
/// [holds] are withheld until the matching completer fires, which is how the
/// gate tests freeze the first scene's downloads.
http.Client _fakeServer({
  bool rpyScript = false,
  bool withSizes = true,
  Map<String, Completer<void>>? holds,
}) {
  final scriptPath = rpyScript ? 'game/script.rpy' : 'game/script.fly';
  final manifest = jsonEncode({
    'version': 1,
    'name': 'Demo',
    'script': scriptPath,
    'files': [scriptPath, ..._imagePaths, _audioPath],
    if (withSizes)
      'sizes': {
        for (final path in _imagePaths) path: _pngBytes.length,
        _audioPath: _opusBytes.length,
      },
  });
  return MockClient((request) async {
    final url = Uri.decodeFull(request.url.toString());
    if (url == '$_base/fly_manifest.json') {
      return http.Response(manifest, 200);
    }
    if (url == '$_base/game/script.fly') {
      return http.Response(_flyScript(), 200);
    }
    if (url == '$_base/game/script.rpy') {
      return http.Response(_script, 200);
    }
    final path =
        url.startsWith('$_base/') ? url.substring('$_base/'.length) : url;
    final hold = holds?[path];
    if (hold != null) await hold.future;
    if (_imagePaths.contains(path)) {
      return http.Response.bytes(_pngBytes, 200);
    }
    if (path == _audioPath) {
      return http.Response.bytes(_opusBytes, 200);
    }
    return http.Response('not found', 404);
  });
}

Map<String, Completer<void>> _holdFirstScene() => {
  for (final path in _imagePaths) path: Completer<void>(),
  _audioPath: Completer<void>(),
};

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  http.Client client, {
  ValueChanged<RenPyFlutterController>? onControllerCreated,
}) {
  SharedPreferences.setMockInitialValues({});
  return tester.pumpWidget(
    MaterialApp(
      home: StreamedGameScreen(
        baseUrl: _base,
        audioPlayback: const RenPyNoOpAudioPlayback(),
        httpClient: client,
        onControllerCreated: onControllerCreated,
      ),
    ),
  );
}

void main() {
  testWidgets('streamed .fly game plays with sprites served from memory', (
    tester,
  ) async {
    RenPyFlutterController? controller;
    await _pumpScreen(
      tester,
      _fakeServer(),
      onControllerCreated: (created) => controller = created,
    );

    await _pumpUntil(
      tester,
      () => find.textContaining('Streamed hello.').evaluate().isNotEmpty,
    );

    expect(find.textContaining('Streamed hello.'), findsOneWidget);
    expect(controller, isNotNull);

    // The first-scene gate guarantees the opening assets are cached before
    // the game starts, so sprites resolve cache-first to MemoryImage — no
    // NetworkImage round-trips.
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.any((image) => image.image is MemoryImage), isTrue);
    expect(images.any((image) => image.image is NetworkImage), isFalse);
  });

  testWidgets('gates on the first scene assets before starting', (
    tester,
  ) async {
    final holds = _holdFirstScene();
    await _pumpScreen(tester, _fakeServer(holds: holds));

    await _pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey('streamed-progress'))
              .evaluate()
              .isNotEmpty,
    );

    // The loading view is up; no dialogue while assets are withheld.
    expect(find.byKey(const ValueKey('streamed-progress')), findsOneWidget);
    expect(find.textContaining('MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('streamed-cancel')), findsOneWidget);
    expect(find.textContaining('Streamed hello.'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Streamed hello.'), findsNothing);

    // Releasing the first scene's bytes starts the game.
    for (final hold in holds.values) {
      hold.complete();
    }
    await _pumpUntil(
      tester,
      () => find.textContaining('Streamed hello.').evaluate().isNotEmpty,
    );

    expect(find.textContaining('Streamed hello.'), findsOneWidget);
    expect(find.byKey(const ValueKey('streamed-progress')), findsNothing);
  });

  testWidgets('gate progress is bytes-based when the manifest has sizes', (
    tester,
  ) async {
    final holds = _holdFirstScene();
    await _pumpScreen(tester, _fakeServer(holds: holds));

    await _pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey('streamed-progress'))
              .evaluate()
              .isNotEmpty,
    );

    var bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('streamed-progress')),
    );
    expect(bar.value, 0);

    // One image lands: progress advances by exactly its manifest size.
    holds[_imagePaths.first]!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('streamed-progress')),
    );
    expect(bar.value, closeTo(_pngBytes.length / _gateTotalBytes, 0.001));

    for (final hold in holds.values) {
      if (!hold.isCompleted) hold.complete();
    }
    await _pumpUntil(
      tester,
      () => find.textContaining('Streamed hello.').evaluate().isNotEmpty,
    );
    expect(find.textContaining('Streamed hello.'), findsOneWidget);
  });

  testWidgets('gate progress falls back to file counts without sizes', (
    tester,
  ) async {
    final holds = _holdFirstScene();
    await _pumpScreen(tester, _fakeServer(withSizes: false, holds: holds));

    await _pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey('streamed-progress'))
              .evaluate()
              .isNotEmpty,
    );

    expect(find.textContaining('files'), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);

    var bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('streamed-progress')),
    );
    expect(bar.value, 0);

    // One of the three gated files lands.
    holds[_imagePaths.first]!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('streamed-progress')),
    );
    expect(bar.value, closeTo(1 / 3, 0.001));

    for (final hold in holds.values) {
      if (!hold.isCompleted) hold.complete();
    }
    await _pumpUntil(
      tester,
      () => find.textContaining('Streamed hello.').evaluate().isNotEmpty,
    );
    expect(find.textContaining('Streamed hello.'), findsOneWidget);
  });

  testWidgets('streamed .rpy game is rejected with a migration hint', (
    tester,
  ) async {
    await _pumpScreen(tester, _fakeServer(rpyScript: true));

    await _pumpUntil(
      tester,
      () => find.textContaining('Could not stream').evaluate().isNotEmpty,
    );

    expect(find.textContaining('Could not stream this game'), findsOneWidget);
  });
}
