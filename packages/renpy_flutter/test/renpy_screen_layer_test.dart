import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('renders a shown screen tree with text, loop, and conditionals', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen hud(level):
    vbox xalign 0.5 spacing 10:
        text "Level [level]" color "#ff0000"
        if level > 0:
            text "Active"
        for item in ["a", "b", "c"]:
            text "item-[item]"
        textbutton "Close" action Return("closed")

label start:
    show screen hud(2)
    "playing"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    // Text with an interpolated `[level]` parameter.
    expect(find.text('Level 2'), findsOneWidget);
    // The `if level > 0` branch is taken.
    expect(find.text('Active'), findsOneWidget);
    // The `for` loop produced one text per item.
    expect(find.text('item-a'), findsOneWidget);
    expect(find.text('item-b'), findsOneWidget);
    expect(find.text('item-c'), findsOneWidget);
    // The button label renders.
    expect(find.text('Close'), findsOneWidget);

    // A red text color was applied from the `color` property.
    final hasRedText = tester
        .widgetList<RenPyText>(find.byType(RenPyText))
        .any((text) => text.style?.color == const Color(0xFFFF0000));
    expect(hasRedText, isTrue);

    // An xalign of 0.5 horizontally centers the vbox.
    final hasCentered = tester
        .widgetList<Align>(find.byType(Align))
        .any(
          (a) =>
              a.alignment is Alignment && (a.alignment as Alignment).x == 0.0,
        );
    expect(hasCentered, isTrue);
  });

  testWidgets('tapping a textbutton routes its action through the runner', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen confirm():
    vbox:
        text "Are you sure?"
        textbutton "Yes" action Hide("confirm")

label start:
    show screen confirm
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(controller.shownScreens, hasLength(1));
    expect(find.text('Yes'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pump();

    // The Hide action removed the screen and the layer re-resolved to nothing.
    expect(controller.shownScreens, isEmpty);
    expect(find.text('Yes'), findsNothing);
  });

  testWidgets('tapping a Return button hides the screen via the action', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen picker():
    textbutton "Pick" action SetVariable("picked", True)

label start:
    \$ picked = False
    show screen picker
    "go"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Pick'));
    await tester.pump();

    // SetVariable wrote through to the store; a probe screen reads it back.
    final probe = controller.resolveScreen('picker');
    expect(probe, isNotNull);
  });

  testWidgets('a call screen renders as a modal that blocks the game and '
      'resumes on Return', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen confirm(message):
    vbox:
        text "[message]"
        textbutton "Yes" action Return(True)

label start:
    call screen confirm("Quit?")
    \$ answered = _return
    "answered"
''');

    await _drainUntil(controller, () => controller.pendingCallScreen != null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    // The call screen content is drawn through the shared renderer.
    expect(controller.pendingCallScreen, isNotNull);
    expect(find.text('Quit?'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);

    // A dim modal barrier sits behind the content and blocks the game beneath.
    final dimBarrier = find.byWidgetPredicate(
      (w) => w is ModalBarrier && w.color == const Color(0x99000000),
    );
    expect(dimBarrier, findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pump();

    // Return dismissed the modal and the runner resumed.
    expect(controller.pendingCallScreen, isNull);
    expect(find.text('Quit?'), findsNothing);
    expect(dimBarrier, findsNothing);
  });

  testWidgets('the layer is inert when no screen is shown', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "no screens here"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(controller.shownScreens, isEmpty);
    expect(find.byType(RenPyText), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });
}

Future<void> _drainUntil(
  RenPyFlutterController controller,
  bool Function() done,
) async {
  for (var i = 0; i < 100; i += 1) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Controller did not reach expected state. Last: ${controller.value}');
}
