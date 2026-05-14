import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('dialogue [var] is interpolated against the store', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    \$ gold = 42
    "You have [gold] coins."
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

    expect(find.text('You have 42 coins.'), findsOneWidget);
    expect(find.text('You have [gold] coins.'), findsNothing);
  });

  testWidgets('[[ escapes to a literal bracket', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "Press [[A] to jump."
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

    expect(find.text('Press [A] to jump.'), findsOneWidget);
  });

  testWidgets('the !u flag upper-cases the interpolated value', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    \$ name = "eileen"
    "Hello [name!u]."
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

    expect(find.text('Hello EILEEN.'), findsOneWidget);
  });

  testWidgets('the typewriter reveal counts interpolated characters', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    \$ gold = 1000
    "[gold]"
''');

    await _pumpUntilDialogue(tester, controller);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenPyDialogueView(controller: controller, textCps: 100),
        ),
      ),
    );

    // Nothing revealed on the first frame.
    expect(_visibleText(tester), isEmpty);

    // At 100 cps, two of the four interpolated digits ("1000") show by 25ms.
    await tester.pump(const Duration(milliseconds: 25));
    expect(_visibleText(tester), '10');

    await tester.pump(const Duration(milliseconds: 200));
    expect(_visibleText(tester), '1000');
  });

  test('RenPyTextInterpolation strips !flag and :format suffixes', () {
    String? resolve(String expression) {
      if (expression == 'name') return 'Bob';
      return null;
    }

    expect(RenPyTextInterpolation.apply('Hi [name!t].', resolve), 'Hi Bob.');
    expect(RenPyTextInterpolation.apply('Hi [name:>10].', resolve), 'Hi Bob.');
    expect(RenPyTextInterpolation.apply('Hi [name!l].', resolve), 'Hi bob.');
    // An unresolved reference is preserved verbatim.
    expect(
      RenPyTextInterpolation.apply('Hi [missing].', resolve),
      'Hi [missing].',
    );
  });
}

String _visibleText(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text).first);
  return (text.textSpan! as TextSpan).toPlainText();
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
