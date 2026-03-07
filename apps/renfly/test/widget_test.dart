import 'package:flutter_test/flutter_test.dart';
import 'package:renfly/main.dart';
import 'package:flutter/widgets.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('launcher lists The Question', (tester) async {
    await _pumpFreshApp(tester);

    expect(find.text('Choose a demo game'), findsOneWidget);
    expect(find.text('The Question'), findsOneWidget);
  });

  testWidgets('launcher opens The Question and renders the first beat', (
    tester,
  ) async {
    await _pumpFreshApp(tester);

    await tester.tap(find.text('The Question'));
    await _pumpUntilFirstLine(tester);

    expect(find.text('the_question'), findsOneWidget);
    expect(
      find.text(
        "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsWidgets);

    final textTop =
        tester
            .getTopLeft(
              find.text(
                "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
              ),
            )
            .dy;
    expect(textTop, greaterThan(350));
  });
}

Future<void> _pumpFreshApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    FiestaVNApp(
      key: UniqueKey(),
      audioPlayback: const RenPyNoOpAudioPlayback(),
    ),
  );
  await tester.pump();
}

Future<void> _pumpUntilFirstLine(WidgetTester tester) async {
  final firstLine = find.text(
    "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
  );

  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (firstLine.evaluate().isNotEmpty) return;
  }

  fail('The Question did not render its first dialogue line.');
}
