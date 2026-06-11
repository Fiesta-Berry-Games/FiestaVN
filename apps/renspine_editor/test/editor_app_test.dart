// Widget and routing tests for the RenSpine Editor.
//
// Spine sprites need the spine_flutter native runtime (FFI/wasm), which is
// unavailable in headless widget tests, so every pumped editor injects
// [spineSuppressingImageLayer] and the suite asserts at the script /
// insertion / routing level instead — the same boundary packages/renpy_spine
// draws in its own tests.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly_editor/renfly_editor.dart';
import 'package:renpy_core/renpy_core.dart' show RenPyImageResolver;
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_spine/renpy_spine.dart';
import 'package:renspine_editor/main.dart';

/// Pumps frames until [condition] holds, failing after [attempts] pumps.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 100,
  String description = 'condition',
}) async {
  for (var i = 0; i < attempts; i += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description');
}

/// Pumps the RenSpine editor with injected seams: no-op audio, an in-memory
/// bundled-art loader ([bundledAssets], empty by default), and the
/// Spine-suppressing preview layer (no Spine native runtime in tests).
Future<void> pumpEditor(
  WidgetTester tester, {
  PickAssetFiles? pickAssets,
  Map<String, Uint8List> bundledAssets = const {},
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RenSpineEditorApp(
      audioPlayback: const RenPyNoOpAudioPlayback(),
      pickAssets: pickAssets,
      loadBundledAssets: () async => bundledAssets,
      imageLayerBuilder: spineSuppressingImageLayer,
    ),
  );
  await tester.pump();
}

/// The script editor's controller.
TextEditingController editorController(WidgetTester tester) =>
    tester
        .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
        .controller!;

void main() {
  testWidgets('app builds with the RenSpine Editor title and a live preview', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Rebranded toolbar, with the inherited RenFly editor controls intact.
    expect(find.text('RenSpine Editor'), findsOneWidget);
    expect(find.text('RenFly Editor'), findsNothing);
    expect(find.byKey(const ValueKey('editor-run-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-gallery-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-examples-button')),
      findsOneWidget,
    );

    // The starter template is loaded and the preview is live from launch.
    expect(editorController(tester).text, starterTemplate);
    expect(find.text('Running'), findsOneWidget);
    await pumpUntil(
      tester,
      () =>
          find.textContaining('Welcome to RenFly Editor.').evaluate().length >=
          2,
      description: 'auto-started preview',
    );
  });

  testWidgets('the default preview layer is the Spine routing layer', (
    tester,
  ) async {
    // Build the layer RenSpineEditorApp wires by default. No script is
    // loaded, so no Spine sprite (and no spine_flutter native runtime) is
    // instantiated: only the routing layer and its suppressing underlay.
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => spinePreviewImageLayer(
                context,
                controller,
                RenPyScreenSize.fallback,
                (assetPath) => AssetImage(assetPath),
              ),
        ),
      ),
    );

    expect(find.byType(SpineImageLayer), findsOneWidget);
    expect(find.byType(RenPyImageLayer), findsOneWidget);
    expect(find.byType(SpineSpriteWidget), findsNothing);
  });

  // ---------------------------------------------------------------
  // Examples menu and the Spine demo
  // ---------------------------------------------------------------

  testWidgets('Examples menu lists the built-in stories plus the Spine demo', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('editor-examples-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('editor-example-starter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-example-the-question')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-example-sylvie-and-sylvie')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-example-spine-demo')),
      findsOneWidget,
    );
    expect(
      find.text('Fiesta rehearsal (Spine two-character demo)'),
      findsOneWidget,
    );
  });

  testWidgets('bundled Spine demo asset parses with zero warnings', (
    tester,
  ) async {
    // Real asset I/O must run outside the test's fake-async zone; cache:
    // false so an earlier widget test cannot leave a poisoned future behind.
    final text =
        (await tester.runAsync(
          () => rootBundle.loadString(
            'assets/examples/spine_demo.rpy',
            cache: false,
          ),
        ))!;
    expect(text, contains('erikari'));
    expect(
      text.startsWith('﻿'),
      isFalse,
      reason: 'the bundled copy must not carry a UTF-8 BOM',
    );

    final result = RenPyParser().parse(text, 'spine_demo.rpy');
    expect(result.warnings, isEmpty);
    expect(result.script.statements, isNotEmpty);
  });

  testWidgets("renfly_editor's bundled examples and art resolve through the "
      'package-prefix fallback', (tester) async {
    // Composed inside this app, renfly_editor's assets live under
    // packages/renfly_editor/ — loadEditorAssetString and the default
    // bundled-art loader fall back to that prefix.
    final question =
        (await tester.runAsync(
          () => loadEditorAssetString('assets/examples/the_question.rpy'),
        ))!;
    expect(question, contains('sylvie'));

    final art = (await tester.runAsync(loadBundledExampleAssets))!;
    expect(art.keys, contains('game/images/sylvie green smile.png'));
    expect(art.values.every((bytes) => bytes.isNotEmpty), isTrue);
  });

  testWidgets('bundled Spine skeleton ships in the asset bundle', (
    tester,
  ) async {
    for (final path in const [
      'assets/chibi-stickers/export/chibi-stickers.atlas',
      'assets/chibi-stickers/export/chibi-stickers-pro.skel',
      'assets/chibi-stickers/export/chibi-stickers-pro.png',
    ]) {
      final data = (await tester.runAsync(() => rootBundle.load(path)))!;
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });

  testWidgets('Spine demo loads, parses clean, and previews without '
      'diagnostics', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('editor-examples-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-example-spine-demo')));
    await tester.pump();

    // The script is loaded asynchronously from the bundled asset.
    final controller = editorController(tester);
    await pumpUntil(
      tester,
      () => controller.text.contains('erikari-emotes/wave.spine'),
      description: 'Spine demo loaded into the editor',
    );

    // The open-path migration flow may surface an informational report.
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('migration-report-confirm'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    // Parsed clean: no errors and no warnings after the debounce.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Parse error'), findsNothing);
    expect(find.textContaining('warning'), findsNothing);

    // The preview auto-runs to the first dialogue line (the text also exists
    // in the editor's TextField, so wait for a second occurrence) ...
    await pumpUntil(
      tester,
      () =>
          find
              .textContaining('Welcome to the RenSpine Editor!')
              .evaluate()
              .length >=
          2,
      attempts: 200,
      description: 'first Spine demo dialogue in the preview',
    );

    // ... with every `.spine` show resolved against the registered virtual
    // assets, so no unresolved-asset diagnostics surface.
    expect(find.byKey(const ValueKey('editor-issues-strip')), findsNothing);
  });

  test('Spine demo image definitions route to the configured characters', () {
    final source = File('assets/examples/spine_demo.rpy').readAsStringSync();
    final script = RenPyParser().parse(source, 'spine_demo.rpy').script;
    final aliases = RenPyImageResolver.aliasesFor(script);
    final charactersByTag = {
      for (final character in kSpineCharacters) character.tag: character,
    };

    final spineAliases = Map.fromEntries(
      aliases.entries.where((entry) => entry.value.endsWith('.spine')),
    );
    expect(spineAliases, isNotEmpty);

    for (final entry in spineAliases.entries) {
      // The controller resolves each defined image to its game-root-joined
      // alias; classify exactly that pair, like the player does.
      final route = classifySpineShow(
        show: entry.key,
        assetPath: 'game/${entry.value}',
        charactersByTag: charactersByTag,
      );
      expect(route, isNotNull, reason: entry.key);
      expect(route!.tag, entry.key.split(' ').first, reason: entry.key);
      expect(
        route.skin,
        route.character.effectiveDefaultSkin,
        reason: entry.key,
      );
    }
  });

  test('spinePreviewAssets covers both resolver spellings of every pose', () {
    final assets = spinePreviewAssets();

    // Image-definition aliases (`Image("erikari-emotes/wave.spine")`) ...
    expect(assets, contains('game/erikari-emotes/wave.spine'));
    expect(assets, contains('game/erikari-movement/idle-front.spine'));
    expect(assets, contains('game/harri-emotes/thinking.spine'));
    // ... and raw gallery insertions (`show erikari erikari-...spine`).
    expect(assets, contains('game/erikari erikari-emotes/wave.spine'));
    expect(assets, contains('game/harri harri-movement/idle-front.spine'));
    expect(
      assets.length,
      kSpineCharacters.length * kSpineAnimations.length * 2,
    );
  });

  // ---------------------------------------------------------------
  // Spine characters gallery section
  // ---------------------------------------------------------------

  testWidgets('character gallery lists the Spine characters with their skins '
      'and animations', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('spine-gallery-section')), findsOneWidget);

    // The Spine section keeps the gallery meaningful with no image assets.
    expect(find.textContaining('No image assets yet'), findsNothing);

    // Each configured character is listed with its skin ...
    expect(find.text('Spine characters'), findsOneWidget);
    expect(find.text('erikari — skin "erikari"'), findsOneWidget);
    expect(find.text('harri — skin "harri"'), findsOneWidget);

    // ... and every catalog animation gets a pose tile with L/C/R shortcuts.
    for (final character in kSpineCharacters) {
      for (final option in kSpineAnimations) {
        final key = 'spine-gallery-show-${character.tag}-${option.label}';
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        for (final position in const ['left', 'center', 'right']) {
          expect(find.byKey(ValueKey('$key-$position')), findsOneWidget);
        }
      }
    }

    // The two-character pair helper is available.
    expect(
      find.byKey(const ValueKey('spine-gallery-pair-left')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spine-gallery-pair-right')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spine-gallery-pair-insert')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('editor-gallery-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsNothing);
  });

  testWidgets('tapping a Spine pose inserts the .spine show at the cursor', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n    "Beta"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller = editorController(tester);
    // Park the cursor in the "Alpha" line (line 2).
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    final wave = find.byKey(const ValueKey('spine-gallery-show-erikari-wave'));
    await tester.ensureVisible(wave);
    await tester.pumpAndSettle();
    await tester.tap(wave);
    await tester.pumpAndSettle();

    // The dialog closed and the show landed on its own line under "Alpha",
    // indented to match the block.
    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsNothing);
    expect(
      controller.text,
      'label start:\n    "Alpha"\n'
      '    show erikari erikari-emotes/wave.spine\n    "Beta"\n',
    );

    // The inserted show hot-reloads without unresolved-asset diagnostics:
    // the `.spine` path is registered as a virtual preview asset.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('editor-issues-strip')), findsNothing);
  });

  testWidgets('L / C / R shortcuts insert positioned Spine shows', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller = editorController(tester);
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    final thinkingRight = find.byKey(
      const ValueKey('spine-gallery-show-harri-thinking-right'),
    );
    await tester.ensureVisible(thinkingRight);
    await tester.pumpAndSettle();
    await tester.tap(thinkingRight);
    await tester.pumpAndSettle();

    expect(
      controller.text,
      'label start:\n    "Alpha"\n'
      '    show harri harri-emotes/thinking.spine at right\n',
    );
  });

  testWidgets('two-character pair helper inserts Spine shows at left and '
      'right', (tester) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller = editorController(tester);
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();

    // Pick the left and right poses, then insert the pair.
    final leftDropdown = find.byKey(const ValueKey('spine-gallery-pair-left'));
    await tester.ensureVisible(leftDropdown);
    await tester.pumpAndSettle();
    await tester.tap(leftDropdown);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('spine-gallery-pair-left-erikari wave')).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spine-gallery-pair-right')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('spine-gallery-pair-right-harri laugh')).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spine-gallery-pair-insert')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsNothing);
    expect(
      controller.text,
      'label start:\n    "Alpha"\n'
      '    show erikari erikari-emotes/wave.spine at left\n'
      '    show harri harri-emotes/laugh.spine at right\n',
    );
  });

  testWidgets('image-asset gallery sections still work alongside the Spine '
      'section', (tester) async {
    // A regular character sprite added to the session shows up in the
    // editor's own gallery grouping, proving the host section is additive.
    final tinyPng = Uint8List.fromList(const [
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
      0x0b, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x60, 0x00, 0x02, 0x00, //
      0x00, 0x05, 0x00, 0x01, 0x7a, 0x5e, 0xab, 0x3f, 0x00, 0x00, 0x00, 0x00, //
      0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ]);
    await pumpEditor(
      tester,
      bundledAssets: {'game/images/sylvie green smile.png': tinyPng},
    );
    await pumpUntil(
      tester,
      () => find.text('1 asset').evaluate().isNotEmpty,
      description: 'preloaded bundled art in the assets chip',
    );

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('editor-gallery-show-sylvie green smile')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('spine-gallery-section')), findsOneWidget);
  });
}
