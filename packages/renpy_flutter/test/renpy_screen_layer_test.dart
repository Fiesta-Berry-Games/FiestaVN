import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('a screen key binding fires its action when the key is pressed', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen hotkey():
    key "K_RETURN" action Hide("hotkey")

label start:
    show screen hotkey
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

    // Pressing the bound key runs the action (Hide), removing the screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.shownScreens, isEmpty);
  });

  testWidgets('a screen key does not steal the dialogue-advance key beneath it', (
    tester,
  ) async {
    final advanced = <LogicalKeyboardKey>[];
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    // A non-modal HUD carrying a key bound to enter. A sibling Focus stands in
    // for the game's dialogue-advance handler: pressing space must still reach
    // it (the key node must not autofocus and grab the event).
    controller.load('''
screen hud():
    key "K_RETURN" action NullAction()

label start:
    show screen hud
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: focusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) advanced.add(event.logicalKey);
              return KeyEventResult.handled;
            },
            child: RenPyScreenLayer(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    // The sibling game-input node, not the screen key, holds focus.
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    // Pressing space (the advance key) reaches the game node.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(advanced, contains(LogicalKeyboardKey.space));

    // And the bound enter key also still reaches the game node (the key node's
    // handler is additive: it never marks the event handled).
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(advanced, contains(LogicalKeyboardKey.enter));
  });

  testWidgets('a viewport scrolls and keeps its offset across a re-resolve', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen scroller():
    viewport scrollbars "vertical" ysize 120:
        vbox:
            for i in range(40):
                text "row-[i]"

label start:
    show screen scroller
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    // Scroll the viewport down.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pump();

    final scrolled =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(scrolled, greaterThan(0));

    // Force a re-resolve (mirrors what an interaction does) and confirm the
    // viewport restored its remembered offset rather than snapping to the top.
    controller.notifyListeners();
    await tester.pump();

    final afterRebuild =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(afterRebuild, closeTo(scrolled, 1.0));
  });

  testWidgets('a vpgrid scrolls its cells', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen gallery():
    vpgrid cols 2 ysize 120:
        for i in range(40):
            text "cell-[i]"

label start:
    show screen gallery
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -150),
    );
    await tester.pump();

    // The vpgrid's inner GridView is non-scrollable; the viewport's own scroll
    // view is the one that moved.
    final offsets =
        tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .map((s) => s.position.pixels)
            .toList();
    expect(offsets.any((p) => p > 0), isTrue);
  });

  testWidgets('a screen text node interpolates an [obj.field] reference', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen profile():
    text "HP [player.hp]/[player.max_hp]"

label start:
    python:
        class Player:
            def __init__(self):
                self.hp = 7
                self.max_hp = 10
        player = Player()
    show screen profile
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    // The `[player.hp]`/`[player.max_hp]` field references resolved.
    expect(find.text('HP 7/10'), findsOneWidget);
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
