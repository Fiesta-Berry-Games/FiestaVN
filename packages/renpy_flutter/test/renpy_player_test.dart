import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets(
    'asset player loads a bundled script and renders the first beat',
    (tester) async {
      final bundle = _MemoryAssetBundle({
        'assets/game/script.rpy': '''
label start:
    scene bg lecturehall
    "Welcome to class."
''',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RenPyAssetPlayer(
            scriptAsset: 'assets/game/script.rpy',
            bundle: bundle,
            availableAssets: const {'assets/game/images/bg lecturehall.png'},
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _pumpUntil(tester, find.text('Welcome to class.'));

      expect(find.text('Welcome to class.'), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(
        (images.single.image as AssetImage).assetName,
        'assets/game/images/bg lecturehall.png',
      );
    },
  );

  testWidgets('asset player can restart the loaded script', (tester) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
    "Second."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await _pumpUntil(tester, find.text('First.'));
    await tester.tap(find.text('First.'));
    await _pumpUntil(tester, find.text('Second.'));

    await tester.tap(find.byTooltip('Restart'));
    await _pumpUntil(tester, find.text('First.'));

    expect(find.text('First.'), findsOneWidget);
    expect(find.text('Second.'), findsNothing);
  });

  testWidgets('asset player supports a custom image layer', (tester) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    show sylvie green normal
    "Hello."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          imageLayerBuilder: (context, controller) {
            return _RecordingImageLayer(controller: controller);
          },
        ),
      ),
    );

    await _pumpUntil(tester, find.text('custom:sylvie green normal'));

    expect(find.text('Hello.'), findsOneWidget);
  });

  testWidgets('asset player wires RenPy audio into the audio layer', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    play music "illurock.opus"
    "Hello."
''',
    });
    final playback = _RecordingAudioPlayback();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          audioPlayback: playback,
        ),
      ),
    );

    await _pumpUntil(tester, find.text('Hello.'));

    expect(playback.calls, [
      const _AudioCall(
        channel: 'music',
        asset: 'illurock.opus',
        assetSourcePath: 'game/illurock.opus',
      ),
    ]);
  });

  testWidgets('asset player resumes automatically after timed RenPy pauses', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    \$ renpy.pause(0.1)
    "After pause."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('After pause.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await _pumpUntil(tester, find.text('After pause.'));

    expect(find.text('After pause.'), findsOneWidget);
  });

  testWidgets('project player renders from an opened RenPy project folder', (
    tester,
  ) async {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('the_question/game/script.rpy', '''
label start:
    play music "illurock.opus"
    scene bg lecturehall
    "Opened folder."
'''),
      RenPyProjectFile(
        'the_question/game/illurock.opus',
        Uint8List.fromList([1, 2, 3]),
      ),
      RenPyProjectFile(
        'the_question/game/images/bg lecturehall.png',
        _transparentPngBytes(),
      ),
    ]);
    final playback = _RecordingAudioPlayback();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          audioPlayback: playback,
          availableAssets: project.availableAssets,
        ),
      ),
    );

    await _pumpUntil(tester, find.text('Opened folder.'));

    expect(find.text('Opened folder.'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(playback.calls, [
      const _AudioCall(
        channel: 'music',
        asset: 'illurock.opus',
        assetSourcePath: 'the_question/game/illurock.opus',
      ),
    ]);
  });

  testWidgets('project player registers project fonts before loading script', (
    tester,
  ) async {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    show text "{font=UglyQua.ttf}Title{/font}" at truecenter
    "After font."
'''),
      RenPyProjectFile(
        'confession/game/UglyQua.ttf',
        Uint8List.fromList([1, 2, 3]),
      ),
    ]);
    final registrarGate = Completer<void>();
    final registrar = _RecordingFontRegistrar(
      beforeFirstRegistrationCompletes: () => registrarGate.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          fontRegistrar: registrar.register,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(registrar.calls.first.family, 'UglyQua.ttf');
    expect(registrar.calls.first.bytes, [1, 2, 3]);
    expect(find.text('Title'), findsNothing);
    expect(find.text('After font.'), findsNothing);

    registrarGate.complete();
    await _pumpUntil(tester, find.text('Title'));

    expect(find.text('After font.'), findsOneWidget);
    expect(registrar.calls.map((call) => call.family), contains('UglyQua.ttf'));
  });

  testWidgets('player replaces and hides tagged text displayables', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    show text "First" as title at truecenter
    \$ renpy.pause()
    show text "Second" as title
    \$ renpy.pause()
    hide title with dissolve
    "Done."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await _pumpUntil(tester, find.text('First'));
    expect(find.text('Second'), findsNothing);

    await tester.tap(find.byType(RenPyPauseView));
    await _pumpUntil(tester, find.text('Second'));
    expect(find.text('First'), findsNothing);

    await tester.tap(find.byType(RenPyPauseView));
    await _pumpUntil(tester, find.text('Done.'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Second'), findsNothing);
  });

  testWidgets('asset player exposes loading and load failure builders', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({});

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/missing/script.rpy',
          bundle: bundle,
          loadingBuilder: (context) => const Text('Loading script...'),
          loadErrorBuilder:
              (context, error, stackTrace) => Text('Load failed: $error'),
        ),
      ),
    );

    expect(find.text('Loading script...'), findsOneWidget);

    await tester.pump();

    expect(
      find.textContaining('Load failed: Missing test asset'),
      findsOneWidget,
    );
  });

  testWidgets('asset player switches script assets without stale dialogue', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/one.rpy': '''
label start:
    "First script."
''',
      'assets/game/two.rpy': '''
label start:
    "Second script."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/one.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );
    await _pumpUntil(tester, find.text('First script.'));

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/two.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Second script.'));

    expect(find.text('Second script.'), findsOneWidget);
    expect(find.text('First script.'), findsNothing);
  });

  testWidgets('asset player does not reload when dependencies are unchanged', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "Stable."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Stable.'));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );
    await tester.pump();

    expect(bundle.loadStringCalls('assets/game/script.rpy'), 1);
  });

  testWidgets('asset player surfaces controller start failures', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    jump missing_label
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await _pumpUntil(tester, find.textContaining('Label not found'));

    expect(find.textContaining('Label not found'), findsOneWidget);
  });

  testWidgets('asset player surfaces parser failures as player errors', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': 'label start:\n\t"Tabs are invalid."',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await _pumpUntil(tester, find.textContaining('Tab characters'));

    expect(find.textContaining('Tab characters'), findsOneWidget);
  });
}

Uint8List _transparentPngBytes() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAFgwJ/lQv3WQAAAABJRU5ErkJggg==',
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }

  fail('Timed out waiting for $finder');
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;
  final Map<String, int> loadStringCallCounts = {};

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loadStringCallCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    final value = assets[key];
    if (value == null) {
      throw FlutterError('Missing test asset: $key');
    }
    return value;
  }

  @override
  Future<ByteData> load(String key) {
    throw UnimplementedError('Binary assets are not used by this test.');
  }

  int loadStringCalls(String key) => loadStringCallCounts[key] ?? 0;
}

class _RecordingAudioPlayback implements RenPyAudioPlayback {
  final List<_AudioCall> calls = [];

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {
    calls.add(
      _AudioCall(
        channel: channel,
        asset: asset,
        assetSourcePath: assetSourcePath,
      ),
    );
  }

  @override
  Future<void> stop({required String channel, String? fadeout}) async {}

  @override
  Future<void> dispose() async {}
}

class _RecordingFontRegistrar {
  _RecordingFontRegistrar({this.beforeFirstRegistrationCompletes});

  final Future<void> Function()? beforeFirstRegistrationCompletes;
  final List<_FontCall> calls = [];

  Future<void> register(String family, Uint8List bytes) async {
    calls.add(_FontCall(family: family, bytes: List<int>.from(bytes)));
    if (calls.length == 1) {
      await beforeFirstRegistrationCompletes?.call();
    }
  }
}

class _FontCall {
  const _FontCall({required this.family, required this.bytes});

  final String family;
  final List<int> bytes;
}

class _AudioCall {
  const _AudioCall({
    required this.channel,
    required this.asset,
    required this.assetSourcePath,
  });

  final String channel;
  final String asset;
  final String assetSourcePath;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _AudioCall &&
            channel == other.channel &&
            asset == other.asset &&
            assetSourcePath == other.assetSourcePath;
  }

  @override
  int get hashCode => Object.hash(channel, asset, assetSourcePath);

  @override
  String toString() {
    return '_AudioCall(channel: $channel, asset: $asset, '
        'assetSourcePath: $assetSourcePath)';
  }
}

class _RecordingImageLayer extends StatefulWidget {
  const _RecordingImageLayer({required this.controller});

  final RenPyFlutterController controller;

  @override
  State<_RecordingImageLayer> createState() => _RecordingImageLayerState();
}

class _RecordingImageLayerState extends State<_RecordingImageLayer> {
  String? show;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    final status = widget.controller.value;
    if (status is RenPyImageChange && status.show != null) {
      setState(() => show = status.show);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = this.show;
    return show == null ? const SizedBox.shrink() : Text('custom:$show');
  }
}
