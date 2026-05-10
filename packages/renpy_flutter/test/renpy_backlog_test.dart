import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  test('backlog accumulates dialogue lines in reading order', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);
    expect(controller.dialogueHistory.map((entry) => entry.text), ['First.']);

    controller.continueGame();
    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
    controller.continueGame();
    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Third.',
    );

    expect(controller.dialogueHistory.map((entry) => entry.text), [
      'First.',
      'Second.',
      'Third.',
    ]);
  });

  test('backlog records character names alongside narration', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
define s = Character("Sylvie")

label start:
    "A narrator line."
    s "A spoken line."
''');

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'A spoken line.',
    );

    expect(controller.dialogueHistory.length, 2);
    expect(controller.dialogueHistory.first.character, isNull);
    expect(controller.dialogueHistory.first.text, 'A narrator line.');
    expect(controller.dialogueHistory.last.character, 'Sylvie');
    expect(controller.dialogueHistory.last.text, 'A spoken line.');
  });

  test('backlog enforces the configured length cap', () async {
    final controller = RenPyFlutterController(backlogLimit: 2);
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Third.',
    );

    expect(controller.dialogueHistory.map((entry) => entry.text), [
      'Second.',
      'Third.',
    ]);
  });

  test('backlog resets when a new script is loaded', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
''');
    await _continueUntil(controller, (status) => status is RenPyDialogue);
    expect(controller.dialogueHistory, hasLength(1));

    controller.load('''
label start:
    "Fresh."
''');
    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(controller.dialogueHistory.map((entry) => entry.text), ['Fresh.']);
  });

  test(
    'backlog restore reseeds to the current line without ahead lines',
    () async {
      final store = RenPyMemoryRunnerSnapshotStore();
      final controller = RenPyFlutterController(snapshotStore: store);
      addTearDown(controller.dispose);

      controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');

      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Second.',
      );
      expect(controller.dialogueHistory.map((entry) => entry.text), [
        'First.',
        'Second.',
      ]);
      expect(await controller.saveGame(), isTrue);

      controller.continueGame();
      await _waitUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Third.',
      );
      expect(controller.dialogueHistory, hasLength(3));

      expect(await controller.loadSavedGame(), isTrue);
      await _waitUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Second.',
      );

      // Restoring re-presents the current line; the backlog should not double
      // append it and should drop lines that were ahead of the restore point.
      expect(controller.dialogueHistory.map((entry) => entry.text), [
        'Second.',
      ]);
    },
  );

  test('rollback trims the backlog to the current line', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
    controller.continueGame();
    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Third.',
    );
    expect(controller.dialogueHistory, hasLength(3));
    expect(controller.canRollback, isTrue);

    expect(controller.rollback(), isTrue);
    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );

    expect(controller.dialogueHistory.map((entry) => entry.text), ['Second.']);
  });

  testWidgets('backlog view renders entries oldest first', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
''');
    await _pumpUntilDialogue(tester, controller, 'First.');
    controller.continueGame();
    await _pumpUntilDialogue(tester, controller, 'Second.');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              RenPyBacklogView(controller: controller, onClose: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('First.'), findsOneWidget);
    expect(find.text('Second.'), findsOneWidget);

    final firstOffset = tester.getTopLeft(find.text('First.')).dy;
    final secondOffset = tester.getTopLeft(find.text('Second.')).dy;
    expect(firstOffset, lessThan(secondOffset));
  });

  testWidgets('backlog button opens and closes the viewer', (tester) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "Hello there."
    "More lines."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await _pumpUntil(tester, find.text('Hello there.'));

    expect(find.byKey(const ValueKey('renpy-backlog-view')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('renpy-open-backlog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('renpy-backlog-view')), findsOneWidget);
    expect(find.text('Hello there.'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('renpy-backlog-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('renpy-backlog-view')), findsNothing);
  });
}

Future<void> _continueUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 50; i++) {
    if (predicate(controller.value)) return;
    if (controller.value is RenPyDialogue) {
      controller.continueGame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}

Future<void> _waitUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 50; i++) {
    if (predicate(controller.value)) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}

Future<void> _pumpUntilDialogue(
  WidgetTester tester,
  RenPyFlutterController controller,
  String text,
) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    final status = controller.value;
    if (status is RenPyDialogue && status.text == text) return;
  }
  fail('Did not reach dialogue "$text". Last: ${controller.value}');
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }

  fail('Timed out waiting for $finder');
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = assets[key];
    if (value == null) {
      throw FlutterError('Missing test asset: $key');
    }
    return value;
  }

  @override
  Future<ByteData> load(String key) {
    throw UnimplementedError('Binary assets are not used by this test.');
  }
}
