import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  test('enabling auto-forward advances an already-revealed line', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    controller.load('''
label start:
    "One."
    "Two."
''');
    expect((controller.value as RenPyDialogue).text, 'One.');
    // The line revealed instantly while auto was still off.
    controller.notifyTextRevealed();

    controller.autoDelay = 0;
    controller.autoForwardEnabled = true;

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect((controller.value as RenPyDialogue).text, 'Two.');
  });
}
