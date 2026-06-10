import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('dialogue renders RenPy bold tags as styled text', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.value = RenPyDialogue(null, '{b}Good Ending{/b}.');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyDialogueView(controller: controller)),
      ),
    );

    expect(find.text('{b}Good Ending{/b}.'), findsNothing);
    expect(find.text('Good Ending.'), findsOneWidget);

    final text = tester.widget<Text>(
      find.descendant(of: find.byType(RenPyText), matching: find.byType(Text)),
    );
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == 'Good Ending').style?.fontWeight,
      FontWeight.bold,
    );
  });

  testWidgets('dialogue hides RenPy control tags', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.value = RenPyDialogue(null, 'Huh?{p=0.3}{nw}');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyDialogueView(controller: controller)),
      ),
    );

    expect(find.text('Huh?{p=0.3}{nw}'), findsNothing);
    expect(find.text('Huh?'), findsOneWidget);
    expect(find.byType(RenPyText), findsOneWidget);
  });
}
