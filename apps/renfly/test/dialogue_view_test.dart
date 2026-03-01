import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly/controller.dart';
import 'package:renfly/widgets/dialogue_view.dart';

void main() {
  testWidgets('dialogue renders RenPy bold tags as styled text', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.value = RenPyDialogue(null, '{b}Good Ending{/b}.');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DialogueView(controller: controller))),
    );

    expect(find.text('{b}Good Ending{/b}.'), findsNothing);
    expect(find.text('Good Ending.'), findsOneWidget);

    final text = tester.widget<Text>(find.byType(Text).last);
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
      MaterialApp(home: Scaffold(body: DialogueView(controller: controller))),
    );

    expect(find.text('Huh?{p=0.3}{nw}'), findsNothing);
    expect(find.text('Huh?'), findsOneWidget);
  });
}
