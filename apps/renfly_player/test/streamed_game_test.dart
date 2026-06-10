import 'dart:convert';

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
    show eileen happy
    e "Streamed hello."
''';

String _flyScript() {
  final parsed = RenPyParser().parse(_script, 'script.rpy').script;
  return const FlyCodec().encodeToString(parsed);
}

http.Client _fakeServer({required bool rpyScript}) {
  final scriptPath = rpyScript ? 'game/script.rpy' : 'game/script.fly';
  final manifest = jsonEncode({
    'version': 1,
    'name': 'Demo',
    'script': scriptPath,
    'files': [
      scriptPath,
      'game/images/bg room.png',
      'game/images/eileen happy.png',
    ],
  });
  return MockClient((request) async {
    final url = request.url.toString();
    if (url == '$_base/fly_manifest.json') {
      return http.Response(manifest, 200);
    }
    if (url == '$_base/game/script.fly') {
      return http.Response(_flyScript(), 200);
    }
    if (url == '$_base/game/script.rpy') {
      return http.Response(_script, 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  testWidgets('streamed .fly game plays and streams images by URL', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    RenPyFlutterController? controller;

    await tester.pumpWidget(
      MaterialApp(
        home: StreamedGameScreen(
          baseUrl: _base,
          audioPlayback: const RenPyNoOpAudioPlayback(),
          httpClient: _fakeServer(rpyScript: false),
          onControllerCreated: (created) => controller = created,
        ),
      ),
    );

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Streamed hello.').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('Streamed hello.'), findsOneWidget);
    expect(controller, isNotNull);

    // Sprites resolve to network URLs under the streaming base.
    final images = tester.widgetList<Image>(find.byType(Image));
    final urls = [
      for (final image in images)
        if (image.image case final NetworkImage network) network.url,
    ];
    expect(urls, contains('$_base/game/images/eileen happy.png'));
  });

  testWidgets('streamed .rpy game is rejected with a migration hint', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: StreamedGameScreen(
          baseUrl: _base,
          audioPlayback: const RenPyNoOpAudioPlayback(),
          httpClient: _fakeServer(rpyScript: true),
        ),
      ),
    );

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Could not stream').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.textContaining('Could not stream this game'), findsOneWidget);
  });
}
