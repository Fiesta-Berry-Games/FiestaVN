import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('tapping mid-reveal completes the line before advancing', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First line."
    "Second line."
''');

    await _pumpUntilDialogue(tester, controller);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenPyDialogueView(controller: controller, textCps: 10),
        ),
      ),
    );

    // Let a few characters reveal, but not the whole line.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('First line.'), findsNothing);

    // First tap completes the reveal rather than advancing.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(find.text('First line.'), findsOneWidget);
    expect((controller.value as RenPyDialogue).text, 'First line.');

    // Second tap advances to the next line.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await _pumpUntil(
      tester,
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second line.',
    );
  });

  testWidgets('instant text speed shows the full line right away', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "Whole line."
''');

    await _pumpUntilDialogue(tester, controller);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenPyDialogueView(controller: controller, textCps: 0),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Whole line.'), findsOneWidget);
  });
}

Future<void> _pumpUntilDialogue(
  WidgetTester tester,
  RenPyFlutterController controller,
) async {
  for (var i = 0; i < 100; i++) {
    if (controller.value is RenPyDialogue) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Controller did not reach dialogue. Last: ${controller.value}');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 100; i++) {
    if (predicate(controller.value)) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('Controller did not reach expected state. Last: ${controller.value}');
}
