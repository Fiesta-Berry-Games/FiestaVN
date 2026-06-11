import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly_editor/main.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

/// No bundled art: real asset I/O can't run inside the fake-async test zone.
Future<Map<String, Uint8List>> noBundledAssets() async => const {};

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

void main() {
  Future<TextEditingController> setUpStory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RenFlyEditorApp(
        audioPlayback: const RenPyNoOpAudioPlayback(),
        loadBundledAssets: noBundledAssets,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "One."\n    "Two."\n    "Three."\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller =
        tester
            .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
            .controller!;
    // Park the cursor on the first dialogue line so the preview shows "One."
    controller.selection = const TextSelection.collapsed(offset: 14);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(
      tester,
      () => find.textContaining('One.').evaluate().length >= 2,
      description: 'preview at One.',
    );
    return controller;
  }

  testWidgets('Skip toggle fast-forwards the editor preview', (tester) async {
    await setUpStory(tester);

    await tester.tap(find.byKey(const ValueKey('renpy-toggle-skip')));
    await tester.pump();

    await pumpUntil(
      tester,
      () => find.textContaining('Three.').evaluate().length >= 2,
      description: 'skip reaching Three.',
    );
  });

  testWidgets('Auto toggle advances the editor preview', (tester) async {
    await setUpStory(tester);

    await tester.tap(find.byKey(const ValueKey('renpy-toggle-auto')));
    await tester.pump();

    await pumpUntil(
      tester,
      attempts: 60,
      () => find.textContaining('Two.').evaluate().length >= 2,
      description: 'auto advancing to Two.',
    );
  });
}
