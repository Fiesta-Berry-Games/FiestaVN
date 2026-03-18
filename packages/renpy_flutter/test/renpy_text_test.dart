import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('RenPyText renders bold tags as styled text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RenPyText('{b}Good Ending{/b}.'))),
    );

    expect(find.text('{b}Good Ending{/b}.'), findsNothing);
    expect(find.text('Good Ending.'), findsOneWidget);

    final text = tester.widget<Text>(find.byType(Text).first);
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == 'Good Ending').style?.fontWeight,
      FontWeight.bold,
    );
  });

  testWidgets('RenPyText renders italic tags as styled text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RenPyText('This is {i}important{/i}.')),
      ),
    );

    expect(find.text('This is important.'), findsOneWidget);

    final text = tester.widget<Text>(find.byType(Text).first);
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == 'important').style?.fontStyle,
      FontStyle.italic,
    );
  });

  testWidgets('RenPyText renders color tags as styled text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RenPyText('{color=#FFF}White{/color}')),
      ),
    );

    expect(find.text('White'), findsOneWidget);

    final text = tester.widget<Text>(find.byType(Text).first);
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == 'White').style?.color,
      Colors.white,
    );
  });

  testWidgets('RenPyText omits control tags from displayed text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RenPyText('Huh?{p=0.3}{nw}'))),
    );

    expect(find.text('Huh?{p=0.3}{nw}'), findsNothing);
    expect(find.text('Huh?'), findsOneWidget);
  });

  test('RenPyTextSpanParser preserves base style on the root span', () {
    const style = TextStyle(color: Colors.red);

    final span = RenPyTextSpanParser.parse('{b}Styled{/b}', style: style);

    expect(span.style, style);
    expect(span.toPlainText(), 'Styled');
  });
}
