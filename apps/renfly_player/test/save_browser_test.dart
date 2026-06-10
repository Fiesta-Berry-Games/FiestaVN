import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly_player/main.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('game menu save browser saves, deletes, and loads a slot', (
    tester,
  ) async {
    var dialogueSeen = false;
    await _pumpFreshApp(
      tester,
      onGameControllerCreated: (created) {
        created.addListener(() {
          if (created.value is RenPyDialogue) dialogueSeen = true;
        });
      },
    );

    await tester.tap(find.byKey(const ValueKey('demo_game_The Question')));
    await _pumpUntil(
      tester,
      () => dialogueSeen,
      description: 'The Question first dialogue',
    );

    // Open the menu and save into the first manual slot.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpUntilText(tester, 'Game Menu');
    await tester.tap(find.text('Save'));
    await _pumpUntilText(tester, 'Quicksave');
    expect(find.text('Slot 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-1')));
    await tester.pumpAndSettle();

    // The slot is no longer empty and now offers a delete action.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('renpy-save-slot-1')),
        matching: find.text('Empty'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('renpy-save-slot-delete-1')),
      findsOneWidget,
    );

    // Re-saving the same slot prompts for overwrite confirmation.
    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-1')));
    await tester.pumpAndSettle();
    expect(find.text('Overwrite save?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Back to the root menu, then load the slot to confirm the wiring.
    await tester.tap(find.text('Back'));
    await _pumpUntilText(tester, 'Resume');
    await tester.tap(find.text('Load'));
    await _pumpUntilText(tester, 'Quicksave');
    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-1')));
    await tester.pumpAndSettle();

    // Loading closes the menu and returns to gameplay.
    expect(find.text('Game Menu'), findsNothing);
  });
}

Future<void> _pumpFreshApp(
  WidgetTester tester, {
  ValueChanged<RenPyFlutterController>? onGameControllerCreated,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    FiestaVNApp(
      key: UniqueKey(),
      onGameControllerCreated: onGameControllerCreated,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for "$text".');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  String description = 'condition',
  int attempts = 80,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (done()) return;
  }
  fail('Timed out waiting for $description.');
}
