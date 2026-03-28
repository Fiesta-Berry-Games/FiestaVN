import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('show statements carry behind clauses separately from at clauses', () {
    final script =
        RenPyParser().parse('''
label start:
    show eri defa2bw at Position(xpos = 0.25) behind enj
    show sha normal behind eri with dissolve
''', 'show.rpy').script;

    final shows = script.findStatements<RenPyShowStatement>((_) => true);

    expect(shows[0].imageName, 'eri defa2bw');
    expect(shows[0].atExpression, 'Position(xpos = 0.25)');
    expect(shows[0].behindExpression, 'enj');
    expect(shows[0].withExpression, isNull);

    expect(shows[1].imageName, 'sha normal');
    expect(shows[1].atExpression, isNull);
    expect(shows[1].behindExpression, 'eri');
    expect(shows[1].withExpression, 'dissolve');
  });

  test(
    'show text statements carry displayable text separately from placement',
    () {
      final script =
          RenPyParser().parse('''
label start:
    show text "{size=96}{color=#FFF}Confession{/color}{/size}" at truecenter behind logo with longdissolve
''', 'show_text.rpy').script;

      final show =
          script.findStatements<RenPyShowStatement>((_) => true).single;

      expect(show.imageName, 'text');
      expect(
        show.displayableText,
        '{size=96}{color=#FFF}Confession{/color}{/size}',
      );
      expect(show.atExpression, 'truecenter');
      expect(show.behindExpression, 'logo');
      expect(show.withExpression, 'longdissolve');
    },
  );

  test('show text statements honor explicit displayable tags', () {
    final script =
        RenPyParser().parse('''
label start:
    show text "Chapter One" as title at truecenter with dissolve
''', 'show_text_as.rpy').script;

    final show = script.findStatements<RenPyShowStatement>((_) => true).single;

    expect(show.imageName, 'title');
    expect(show.displayableText, 'Chapter One');
    expect(show.atExpression, 'truecenter');
    expect(show.withExpression, 'dissolve');
  });

  test('image statements carry onlayer clauses separately from names', () {
    final script =
        RenPyParser().parse('''
label start:
    show meta onlayer belowmid with longdissolve
    show text "Chapter One" as title onlayer abovemid at truecenter
    hide logo onlayer abovemid with dissolve
''', 'show_onlayer.rpy').script;

    final shows = script.findStatements<RenPyShowStatement>((_) => true);
    final hide = script.findStatements<RenPyHideStatement>((_) => true).single;

    expect(shows[0].imageName, 'meta');
    expect(shows[0].onLayerExpression, 'belowmid');
    expect(shows[0].withExpression, 'longdissolve');

    expect(shows[1].imageName, 'title');
    expect(shows[1].displayableText, 'Chapter One');
    expect(shows[1].onLayerExpression, 'abovemid');
    expect(shows[1].atExpression, 'truecenter');

    expect(hide.imageName, 'logo');
    expect(hide.onLayerExpression, 'abovemid');
    expect(hide.withExpression, 'dissolve');
  });
}
