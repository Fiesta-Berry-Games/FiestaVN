import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('browser lists quicksave and manual slots', (tester) async {
    final controller = RenPyFlutterController(
      slotStore: RenPyMemoryRunnerSnapshotSlotStore(),
    );
    addTearDown(controller.dispose);

    await _pumpBrowser(tester, controller, RenPySaveBrowserMode.save);

    expect(find.text('Quicksave'), findsOneWidget);
    for (
      var index = 1;
      index <= RenPySaveBrowser.defaultManualSlotCount;
      index++
    ) {
      expect(find.text('Slot $index'), findsOneWidget);
    }
    expect(find.text('Empty'), findsNWidgets(7));
  });

  testWidgets('tapping an empty slot saves the current state', (tester) async {
    final store = RenPyMemoryRunnerSnapshotSlotStore();
    final controller = await _loadedController(store);
    addTearDown(controller.dispose);

    await _pumpBrowser(tester, controller, RenPySaveBrowserMode.save);

    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-1')));
    await tester.pumpAndSettle();

    final slots = await store.list();
    expect(slots.single.slot, '1');
    expect(slots.single.preview, 'First.');
    expect(find.text('Empty'), findsNWidgets(6));
  });

  testWidgets('overwriting an occupied slot asks for confirmation', (
    tester,
  ) async {
    final store = RenPyMemoryRunnerSnapshotSlotStore();
    final controller = await _loadedController(store);
    addTearDown(controller.dispose);
    await controller.saveToSlot('1');

    await _pumpBrowser(tester, controller, RenPySaveBrowserMode.save);

    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-1')));
    await tester.pumpAndSettle();
    expect(find.text('Overwrite save?'), findsOneWidget);

    await tester.tap(find.text('Overwrite'));
    await tester.pumpAndSettle();
    expect((await store.list()).single.slot, '1');
  });

  testWidgets('tapping a populated slot in load mode loads it', (tester) async {
    final store = RenPyMemoryRunnerSnapshotSlotStore();
    final controller = await _loadedController(store);
    addTearDown(controller.dispose);

    // Advance and save into slot 1, then move on.
    controller.continueGame();
    await _settle(controller, 'Second.');
    await controller.saveToSlot('1');
    controller.continueGame();
    await _settle(controller, 'Third.');

    var closed = false;
    await _pumpBrowser(
      tester,
      controller,
      RenPySaveBrowserMode.load,
      onClose: () => closed = true,
    );

    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-1')));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect((controller.value as RenPyDialogue).text, 'Second.');
  });

  testWidgets('deleting a populated slot clears it', (tester) async {
    final store = RenPyMemoryRunnerSnapshotSlotStore();
    final controller = await _loadedController(store);
    addTearDown(controller.dispose);
    await controller.saveToSlot('2');

    await _pumpBrowser(tester, controller, RenPySaveBrowserMode.save);
    expect(
      find.byKey(const ValueKey('renpy-save-slot-delete-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('renpy-save-slot-delete-2')));
    await tester.pumpAndSettle();

    expect(await store.list(), isEmpty);
    expect(find.text('Empty'), findsNWidgets(7));
  });
}

Future<void> _pumpBrowser(
  WidgetTester tester,
  RenPyFlutterController controller,
  RenPySaveBrowserMode mode, {
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RenPySaveBrowser(
          controller: controller,
          mode: mode,
          onClose: onClose ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<RenPyFlutterController> _loadedController(
  RenPyRunnerSnapshotSlotStore store,
) async {
  final controller = RenPyFlutterController(slotStore: store);
  controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');
  await _settle(controller, 'First.');
  return controller;
}

Future<void> _settle(RenPyFlutterController controller, String text) async {
  for (var i = 0; i < 50; i++) {
    final status = controller.value;
    if (status is RenPyDialogue && status.text == text) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Controller did not reach "$text". Last: ${controller.value}');
}
