import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets(
    'dialogue view renders character, styled text, and advances on tap',
    (tester) async {
      var continued = false;
      final controller = _TestController(onContinue: () => continued = true);
      addTearDown(controller.dispose);

      controller.value = RenPyDialogue('Sylvie', '{b}Good Ending{/b}.');

      await tester.pumpWidget(
        MaterialApp(home: RenPyDialogueView(controller: controller)),
      );

      expect(find.text('Sylvie'), findsOneWidget);
      expect(find.text('Good Ending.'), findsOneWidget);
      expect(find.text('{b}Good Ending{/b}.'), findsNothing);

      await tester.tap(find.text('Good Ending.'));

      expect(continued, isTrue);
    },
  );

  testWidgets('dialogue view renders character names with RenPy colors', (
    tester,
  ) async {
    final controller = _TestController();
    addTearDown(controller.dispose);

    controller.value = RenPyDialogue(
      'Sylvie',
      'Hi there!',
      characterId: 's',
      color: '#c8ffc8',
    );

    await tester.pumpWidget(
      MaterialApp(home: RenPyDialogueView(controller: controller)),
    );

    final name = tester.widget<Text>(find.text('Sylvie'));
    expect(name.style?.color, const Color(0xFFC8FFC8));
  });

  testWidgets('dialogue view renders errors and hides non-dialogue states', (
    tester,
  ) async {
    final controller = _TestController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyDialogueView(controller: controller)),
    );

    expect(find.byType(Text), findsNothing);

    controller.value = RenPyError('broken script');
    await tester.pump();

    expect(find.text('Error: broken script'), findsOneWidget);
  });

  testWidgets('menu selector renders captions and forwards choices', (
    tester,
  ) async {
    int? selected;
    final controller = _TestController();
    addTearDown(controller.dispose);

    controller.value = RenPyMenu(
      const ['Ask now.', 'Ask later.'],
      (index) => selected = index,
      caption: 'As soon as she catches my eye, I decide...',
    );

    await tester.pumpWidget(
      MaterialApp(home: RenPyMenuSelector(controller: controller)),
    );

    expect(
      find.text('As soon as she catches my eye, I decide...'),
      findsOneWidget,
    );
    expect(find.text('Ask now.'), findsOneWidget);
    expect(find.text('Ask later.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu_choice_1')));

    expect(selected, 1);
  });
}

class _TestController extends RenPyFlutterController {
  _TestController({this.onContinue});

  final VoidCallback? onContinue;

  @override
  void continueGame() {
    onContinue?.call();
  }
}
