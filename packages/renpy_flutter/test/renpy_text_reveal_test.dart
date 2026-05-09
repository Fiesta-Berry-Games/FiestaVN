import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('reveals text progressively at the configured cps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RenPyTextReveal('Hello', cps: 100)),
      ),
    );

    // First frame reveals nothing yet.
    expect(_visibleText(tester), isEmpty);

    // At 100 cps a character is revealed every 10ms.
    await tester.pump(const Duration(milliseconds: 25));
    expect(_visibleText(tester), 'He');

    await tester.pump(const Duration(milliseconds: 200));
    expect(_visibleText(tester), 'Hello');
  });

  testWidgets('instant speed reveals the full line immediately', (
    tester,
  ) async {
    var revealed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenPyTextReveal(
            'Hello',
            cps: 0,
            onRevealed: () => revealed = true,
          ),
        ),
      ),
    );

    expect(_visibleText(tester), 'Hello');
    expect(revealed, isTrue);
  });

  testWidgets('controller.complete finishes the reveal early', (tester) async {
    final controller = RenPyTextRevealController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenPyTextReveal('Hello', cps: 10, controller: controller),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 120));
    expect(_visibleText(tester), isNot('Hello'));
    expect(controller.isComplete, isFalse);

    controller.complete();
    await tester.pump();
    expect(_visibleText(tester), 'Hello');
    expect(controller.isComplete, isTrue);
  });

  testWidgets('preserves inline styles while revealing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RenPyTextReveal('{b}Hi{/b} there', cps: 1000)),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));
    final text = tester.widget<Text>(find.byType(Text));
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style?.fontWeight, FontWeight.bold);
  });
}

String _visibleText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  return (text.textSpan! as TextSpan).toPlainText();
}
