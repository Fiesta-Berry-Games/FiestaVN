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
}
