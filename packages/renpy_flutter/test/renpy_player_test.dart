import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
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

  testWidgets('asset player save and load buttons restore snapshots', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
    "Second."
    "Third."
''',
    });
    final snapshotStore = RenPyMemoryRunnerSnapshotStore();

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          snapshotStore: snapshotStore,
        ),
      ),
    );

    await _pumpUntil(tester, find.text('First.'));
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.byTooltip('Load'), findsOneWidget);

    await tester.tap(find.text('First.'));
    await _pumpUntil(tester, find.text('Second.'));
    await tester.tap(find.byTooltip('Save'));
    await tester.pump();

    await tester.tap(find.byTooltip('Restart'));
    await _pumpUntil(tester, find.text('First.'));

    await tester.tap(find.byTooltip('Load'));
    await _pumpUntil(tester, find.text('Second.'));

    await tester.tap(find.text('Second.'));
    await _pumpUntil(tester, find.text('Third.'));
  });

  testWidgets('asset player rollback button restores previous dialogue', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
    "Second."
    "Third."
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
    expect(find.byTooltip('Rollback'), findsNothing);

    await tester.tap(find.text('First.'));
    await _pumpUntil(tester, find.text('Second.'));
    expect(find.byTooltip('Rollback'), findsOneWidget);

    await tester.tap(find.byTooltip('Rollback'));
    await _pumpUntil(tester, find.text('First.'));

    expect(find.text('First.'), findsOneWidget);
    expect(find.text('Second.'), findsNothing);
  });

  testWidgets('asset player page-up key restores previous dialogue', (
    tester,
  ) async {
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

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await _pumpUntil(tester, find.text('First.'));

    expect(find.text('First.'), findsOneWidget);
    expect(find.text('Second.'), findsNothing);
  });

  testWidgets('asset player upward mouse wheel restores previous dialogue', (
    tester,
  ) async {
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

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(10, 10),
        scrollDelta: Offset(0, -20),
      ),
    );
    await _pumpUntil(tester, find.text('First.'));

    expect(find.text('First.'), findsOneWidget);
    expect(find.text('Second.'), findsNothing);
  });

  testWidgets('asset player escape key opens and resumes game menu', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
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
    expect(find.text('Game Menu'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntil(tester, find.text('Game Menu'));

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Load'), findsNothing);
    expect(find.text('Restart'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(find.text('Game Menu'), findsNothing);
    expect(find.text('First.'), findsOneWidget);
  });

  testWidgets('asset player right-click opens game menu', (tester) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
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

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: tester.getCenter(find.text('First.')));
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.down(tester.getCenter(find.text('First.')));
    await tester.pump();
    await gesture.up();

    await _pumpUntil(tester, find.text('Game Menu'));

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
  });

  testWidgets('asset player game menu save load and restart use snapshots', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
    "Second."
    "Third."
''',
    });
    final snapshotStore = RenPyMemoryRunnerSnapshotStore();

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          snapshotStore: snapshotStore,
        ),
      ),
    );

    await _pumpUntil(tester, find.text('First.'));
    await tester.tap(find.text('First.'));
    await _pumpUntil(tester, find.text('Second.'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntil(tester, find.text('Game Menu'));

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Load'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Restart'));
    await _pumpUntil(tester, find.text('First.'));

    expect(find.text('Game Menu'), findsNothing);
    expect(find.text('Second.'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntil(tester, find.text('Game Menu'));
    await tester.tap(find.text('Load'));
    await _pumpUntil(tester, find.text('Second.'));

    expect(find.text('First.'), findsNothing);
    expect(find.text('Second.'), findsOneWidget);
  });

  testWidgets('asset player game menu blocks rollback wheel input', (
    tester,
  ) async {
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

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntil(tester, find.text('Game Menu'));
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(10, 10),
        scrollDelta: Offset(0, -20),
      ),
    );
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    expect(find.text('First.'), findsNothing);
    expect(find.text('Second.'), findsOneWidget);
  });

  testWidgets('asset player m key toggles music mute preference', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    play music "illurock.opus"
    "First."
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

    await _pumpUntil(tester, find.text('First.'));
    expect(playback.mixerCalls.where((call) => call.channel == 'music'), [
      const _MixerCall(channel: 'music', volume: 1, muted: false),
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();

    expect(playback.mixerCalls.where((call) => call.channel == 'music'), [
      const _MixerCall(channel: 'music', volume: 1, muted: false),
      const _MixerCall(channel: 'music', volume: 1, muted: true),
      const _MixerCall(channel: 'music', volume: 1, muted: false),
    ]);
  });

  testWidgets('asset player game menu preferences toggle music mute', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    play music "illurock.opus"
    "First."
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

    await _pumpUntil(tester, find.text('First.'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntil(tester, find.text('Game Menu'));

    await tester.tap(find.text('Preferences'));
    await _pumpUntil(tester, find.text('Preferences'));
    expect(find.text('Music Muted'), findsOneWidget);

    await tester.tap(find.text('Music Muted'));
    await tester.pump();

    expect(
      playback.mixerCalls.lastWhere((call) => call.channel == 'music'),
      const _MixerCall(channel: 'music', volume: 1, muted: true),
    );
  });

  testWidgets('asset player game menu preferences change music volume', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    play music "illurock.opus"
    "First."
''',
    });
    final playback = _RecordingAudioPlayback();
    final preferenceStore = RenPyMemoryPreferenceStore();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          audioPlayback: playback,
          preferenceStore: preferenceStore,
        ),
      ),
    );

    await _pumpUntil(tester, find.text('First.'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntil(tester, find.text('Game Menu'));
    await tester.tap(find.text('Preferences'));
    await _pumpUntil(tester, find.text('Preferences'));

    final musicSlider = find.byKey(
      const ValueKey('renpy-preference-music-volume'),
    );
    expect(musicSlider, findsOneWidget);

    final slider = tester.widget<Slider>(musicSlider);
    slider.onChanged?.call(0.4);
    await tester.pump();

    expect(
      playback.mixerCalls.lastWhere((call) => call.channel == 'music'),
      const _MixerCall(channel: 'music', volume: 0.4, muted: false),
    );
    final restored = RenPyPlayerPreferences.fromJson(preferenceStore.load());
    expect(
      restored.mixerVolume(RenPyPlayerPreferences.musicMixer),
      closeTo(0.4, 0.001),
    );
  });

  testWidgets('asset player restores persisted music mute preference', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    play music "illurock.opus"
    "First."
''',
    });
    final preferenceStore = RenPyMemoryPreferenceStore();
    final firstPlayback = _RecordingAudioPlayback();
    final secondPlayback = _RecordingAudioPlayback();
    addTearDown(firstPlayback.dispose);
    addTearDown(secondPlayback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          audioPlayback: firstPlayback,
          preferenceStore: preferenceStore,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('First.'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          audioPlayback: secondPlayback,
          preferenceStore: preferenceStore,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('First.'));

    expect(
      secondPlayback.mixerCalls.firstWhere((call) => call.channel == 'music'),
      const _MixerCall(channel: 'music', volume: 1, muted: true),
    );
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

  testWidgets('asset player exposes its controller for harnesses', (
    tester,
  ) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "Harnessed."
''',
    });
    RenPyFlutterController? controller;
    final statuses = <RenPyGameStatus>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
          onControllerCreated: (created) {
            controller = created;
            created.addListener(() => statuses.add(created.value));
          },
        ),
      ),
    );

    await _pumpUntil(tester, find.text('Harnessed.'));

    expect(controller, isNotNull);
    expect(statuses, contains(isA<RenPyDialogue>()));
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

  testWidgets('project player preserves configured RenPy aspect ratio', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('wide/game/options.rpy', '''
define config.screen_width = 800
define config.screen_height = 600
'''),
      RenPyProjectFile.text('wide/game/script.rpy', '''
label start:
    scene black
    "Aspect locked."
'''),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(project: project, showRestartButton: false),
      ),
    );

    await _pumpUntil(tester, find.text('Aspect locked.'));

    final stage = find.byKey(const ValueKey('renpy-player-stage'));
    expect(stage, findsOneWidget);
    expect(tester.getSize(stage), const Size(800, 600));
    expect(tester.getCenter(stage), const Offset(600, 300));
  });

  testWidgets('project player applies RenPy GUI dialogue text metadata', (
    tester,
  ) async {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/options.rpy', '''
define gui.text_font = "UglyQua.ttf"
define config.screen_width = 1280
define config.screen_height = 960
define gui.text_size = 48
define gui.text_color = '#d1aaaa'
define gui.dialogue_text_outlines = [ (0, "#000000", 3, 3) ]
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Styled by GUI."
'''),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: RenPyProjectPlayer(project: project)),
    );

    await _pumpUntil(tester, find.text('Styled by GUI.'));

    final renpyText = tester.widget<RenPyText>(find.byType(RenPyText));
    expect(renpyText.style?.fontFamily, 'UglyQua.ttf');
    expect(renpyText.style?.fontSize, closeTo(30, 0.01));
    expect(renpyText.style?.color, const Color(0xFFD1AAAA));
    expect(renpyText.style?.shadows, isNotEmpty);
  });

  testWidgets('project player constrains long scaled GUI dialogue', (
    tester,
  ) async {
    final longDialogue = List.filled(160, 'Long dialogue').join(' ');
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/options.rpy', '''
define config.screen_width = 1280
define config.screen_height = 960
define gui.text_size = 48
define gui.text_color = '#ffffff'
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "$longDialogue"
'''),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: RenPyProjectPlayer(project: project)),
    );

    await _pumpUntil(tester, find.text(longDialogue));

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(RenPyDialogueView),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('project player exposes its controller for harnesses', (
    tester,
  ) async {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('project/game/script.rpy', '''
label start:
    "Project harnessed."
'''),
    ]);
    RenPyFlutterController? controller;
    final statuses = <RenPyGameStatus>[];

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          onControllerCreated: (created) {
            controller = created;
            created.addListener(() => statuses.add(created.value));
          },
        ),
      ),
    );

    await _pumpUntil(tester, find.text('Project harnessed.'));

    expect(controller, isNotNull);
    expect(statuses, contains(isA<RenPyDialogue>()));
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
  final List<_MuteCall> muteCalls = [];
  final List<_MixerCall> mixerCalls = [];

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadein,
    String? mixer,
    String? fadeout,
    String? volume,
    bool? loop,
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
  Future<void> setMuted({required String channel, required bool muted}) async {
    muteCalls.add(_MuteCall(channel: channel, muted: muted));
  }

  @override
  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  }) async {
    mixerCalls.add(_MixerCall(channel: channel, volume: volume, muted: muted));
  }

  @override
  Future<void> dispose() async {}
}

class _MuteCall {
  const _MuteCall({required this.channel, required this.muted});

  final String channel;
  final bool muted;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _MuteCall && channel == other.channel && muted == other.muted;
  }

  @override
  int get hashCode => Object.hash(channel, muted);

  @override
  String toString() => '_MuteCall(channel: $channel, muted: $muted)';
}

class _MixerCall {
  const _MixerCall({
    required this.channel,
    required this.volume,
    required this.muted,
  });

  final String channel;
  final double volume;
  final bool muted;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _MixerCall &&
            channel == other.channel &&
            volume == other.volume &&
            muted == other.muted;
  }

  @override
  int get hashCode => Object.hash(channel, volume, muted);

  @override
  String toString() =>
      '_MixerCall(channel: $channel, volume: $volume, muted: $muted)';
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
