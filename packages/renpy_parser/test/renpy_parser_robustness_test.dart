import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('multi-line bracketed expressions', () {
    test('joins a `\$` list literal spanning several physical lines', () {
      final result = RenPyParser().parse('''
label start:
    \$ x = [
        "a",
        "b",
    ]
    "done"
''', 'multiline.rpy');

      expect(result.warnings, isEmpty);

      final defines = result.script.findStatements<RenPyDefineStatement>(
        (stmt) => stmt.name == 'x',
      );
      expect(defines, hasLength(1));
      // The list literal must be joined into one logical line with balanced
      // brackets.
      final expression = defines.single.expression;
      expect(
        '['.allMatches(expression).length,
        ']'.allMatches(expression).length,
      );
      expect(expression, contains('"a"'));
      expect(expression, contains('"b"'));
    });

    test('joins a dict literal spanning several physical lines', () {
      final result = RenPyParser().parse('''
label start:
    \$ d = {
        "k": 1,
        "j": 2,
    }
''', 'multiline_dict.rpy');

      expect(result.warnings, isEmpty);
      final define =
          result.script
              .findStatements<RenPyDefineStatement>((stmt) => stmt.name == 'd')
              .single;
      expect(
        '{'.allMatches(define.expression).length,
        '}'.allMatches(define.expression).length,
      );
    });

    test('a comment containing stray quotes and brackets does not abort', () {
      // Previously the apostrophe and parentheses inside the trailing comment
      // corrupted the quote/bracket state and threw a fatal error.
      final result = RenPyParser().parse('''
label start:
    e "Hello there." # It's a comment (with) [stray] 'quotes' and brackets
    "next"
''', 'comment.rpy');

      final says = result.script.findStatements<RenPySayStatement>((_) => true);
      expect(says, hasLength(2));
      expect(says.first.text, 'Hello there.');
    });

    test('a previously-crashing multi-line call snippet parses cleanly', () {
      // A call literal with a comment and an apostrophe inside it, split over
      // several lines: the combination used to crash the lexer.
      const snippet = '''
label stage7:
    call screen text_over_black_bg_screen(
        _('It\\'s a prologue'),  # don't choke on this
        delay=2.0,
    )
    "afterwards"
''';

      late RenPyParseResult result;
      expect(
        () => result = RenPyParser().parse(snippet, 'snippet.rpy'),
        returnsNormally,
      );
      // Zero fatal errors: parsing completed and produced statements.
      expect(result.script.statements, isNotEmpty);
    });
  });

  group('init python in <store> and BOM', () {
    test('accepts an `in <store>` clause on init python', () {
      final result = RenPyParser().parse('''
init -100 python in gui:
    \$ value = 1
''', 'init_store.rpy');

      expect(result.warnings, isEmpty);
      final init =
          result.script.findStatements<RenPyInitStatement>((_) => true).single;
      expect(init.priority, -100);
      expect(init.isPython, isTrue);
    });

    test('strips a leading UTF-8 BOM before matching statements', () {
      final result = RenPyParser().parse(
        '\u{FEFF}'
            'init python:\n'
            '    \$ value = 1\n',
        'bom.rpy',
      );

      expect(result.warnings, isEmpty);
      final inits = result.script.findStatements<RenPyInitStatement>(
        (_) => true,
      );
      expect(inits, hasLength(1));
      expect(inits.single.isPython, isTrue);
    });
  });

  group('window control statements', () {
    test(
      'window show / window hide / window auto parse to window statements',
      () {
        final result = RenPyParser().parse('''
label start:
    window show
    "talk"
    window hide
    window auto
''', 'window.rpy');

        expect(result.warnings, isEmpty);
        final windows = result.script.findStatements<RenPyWindowStatement>(
          (_) => true,
        );
        expect(windows.map((w) => w.action), [
          RenPyWindowAction.show,
          RenPyWindowAction.hide,
          RenPyWindowAction.auto,
        ]);
      },
    );
  });

  group('pause statements', () {
    test('pause accepts leading-dot, decimal, integer and bare forms', () {
      final result = RenPyParser().parse('''
label start:
    pause .25
    pause 0.5
    pause 2
    pause
''', 'pause.rpy');

      expect(result.warnings, isEmpty);
      final pauses = result.script.findStatements<RenPyPauseStatement>(
        (_) => true,
      );
      expect(pauses.map((p) => p.duration), ['.25', '0.5', '2', null]);
    });
  });

  group('image statements', () {
    test('image name = expression keeps the assignment form', () {
      final result = RenPyParser().parse(
        'image eileen happy = "eileen_happy.png"\n',
        'image_assign.rpy',
      );

      expect(result.warnings, isEmpty);
      final image =
          result.script.findStatements<RenPyImageStatement>((_) => true).single;
      expect(image.name, 'eileen happy');
      expect(image.expression, '"eileen_happy.png"');
      expect(image.body, isEmpty);
    });

    test('image name: captures an ATL body instead of crashing', () {
      final result = RenPyParser().parse('''
image eileen blink:
    "eileen_open.png"
    pause 0.5
    "eileen_closed.png"
    repeat
''', 'image_atl.rpy');

      expect(result.warnings, isEmpty);
      final image =
          result.script.findStatements<RenPyImageStatement>((_) => true).single;
      expect(image.name, 'eileen blink');
      expect(image.expression, isEmpty);
      expect(image.body, [
        '"eileen_open.png"',
        'pause 0.5',
        '"eileen_closed.png"',
        'repeat',
      ]);
    });
  });
}
