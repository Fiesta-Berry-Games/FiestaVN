import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

RenPyParseResult _parse(String body) {
  return RenPyParser().parse('''
label start:
$body
''', 'sample.rpy');
}

List<RenPySayStatement> _say(RenPyParseResult result) {
  return result.script.findStatements<RenPySayStatement>((_) => true);
}

void main() {
  group('say statement sprite attributes', () {
    test('captures speaker and attributes for `e happy "..."`', () {
      final result = _parse('    e happy "Hi"');
      final say = _say(result);
      expect(say, hasLength(1));
      expect(say.first.character, 'e');
      expect(say.first.text, 'Hi');
      expect(say.first.attributes, ['happy']);
      expect(result.warnings, isEmpty);
    });

    test('captures `-` prefixed attributes for `e -happy "..."`', () {
      final result = _parse('    e -happy "Hi"');
      final say = _say(result);
      expect(say, hasLength(1));
      expect(say.first.character, 'e');
      expect(say.first.text, 'Hi');
      expect(say.first.attributes, ['-happy']);
    });

    test('plain `e "..."` still parses with no attributes', () {
      final say = _say(_parse('    e "Hi"'));
      expect(say.first.character, 'e');
      expect(say.first.text, 'Hi');
      expect(say.first.attributes, isEmpty);
    });
  });

  group('triple-quoted dialogue', () {
    test('`e """hi"""` captures `hi`', () {
      final say = _say(_parse('    e """hi"""'));
      expect(say.first.character, 'e');
      expect(say.first.text, 'hi');
    });

    test('multi-line triple-quoted body preserves newlines', () {
      final result = RenPyParser().parse('''
label start:
    e """line one
line two"""
''', 'sample.rpy');
      final say = _say(result);
      expect(say.first.character, 'e');
      expect(say.first.text, 'line one\nline two');
    });

    test('narrator triple-quoted body parses', () {
      final say = _say(_parse('    """just narration"""'));
      expect(say.first.character, isNull);
      expect(say.first.text, 'just narration');
    });
  });

  group('escape handling in dialogue', () {
    String unescaped(String literal) {
      // The say text capture stores the raw escapes; parsing exercises
      // _unescapeString on the captured body.
      final say = _say(_parse('    "$literal"'));
      return say.first.text!;
    }

    test('literal backslash + n is not turned into a newline', () {
      expect(unescaped(r'a\\nb'), r'a\nb');
    });

    test('literal backslash + t is not turned into a tab', () {
      expect(unescaped(r'a\\tb'), r'a\tb');
    });

    test('double backslash collapses to one', () {
      expect(unescaped(r'a\\\\b'), r'a\\b');
    });

    test('escaped backslash before a quote escape', () {
      expect(unescaped(r'a\\\"b'), r'a\"b');
    });

    test('real escapes still resolve', () {
      expect(unescaped(r'a\nb'), 'a\nb');
      expect(unescaped(r'a\tb'), 'a\tb');
    });
  });

  group('jump/call expression', () {
    test('jump expression captures the dynamic target', () {
      final result = _parse('    jump expression foo');
      final jumps = result.script.findStatements<RenPyJumpStatement>(
        (_) => true,
      );
      expect(jumps.first.target, 'foo');
      expect(jumps.first.isExpression, isTrue);
    });

    test('call expression captures the dynamic target', () {
      final result = _parse('    call expression bar');
      final calls = result.script.findStatements<RenPyCallStatement>(
        (_) => true,
      );
      expect(calls.first.target, 'bar');
      expect(calls.first.isExpression, isTrue);
    });

    test('plain jump/call labels remain non-dynamic', () {
      final result = _parse('    jump other\n    call helper');
      final jumps = result.script.findStatements<RenPyJumpStatement>(
        (_) => true,
      );
      final calls = result.script.findStatements<RenPyCallStatement>(
        (_) => true,
      );
      expect(jumps.first.target, 'other');
      expect(jumps.first.isExpression, isFalse);
      expect(calls.first.target, 'helper');
      expect(calls.first.isExpression, isFalse);
    });
  });

  group('keyword word boundaries', () {
    test('identifiers starting with keywords do not warn', () {
      final result = RenPyParser().parse('''
define scenery_thing = 1
define menuitem = 2
init python:
    initialize = 3
''', 'sample.rpy');
      expect(
        result.warnings.where(
          (w) =>
              w.contains('scene') || w.contains('menu') || w.contains('init'),
        ),
        isEmpty,
      );
    });

    test('real scene/menu/init still parse', () {
      final result = RenPyParser().parse('''
init python:
    pass
label start:
    scene bg room
    menu:
        "Choice":
            pass
''', 'sample.rpy');
      expect(
        result.script.findStatements<RenPySceneStatement>((_) => true),
        hasLength(1),
      );
      expect(
        result.script.findStatements<RenPyMenuStatement>((_) => true),
        hasLength(1),
      );
      expect(
        result.script.findStatements<RenPyInitStatement>((_) => true),
        hasLength(1),
      );
    });
  });

  group('define/default priority prefix', () {
    test('define accepts an integer priority', () {
      final result = RenPyParser().parse('define -1 foo = bar', 'sample.rpy');
      final defines = result.script.findStatements<RenPyDefineStatement>(
        (_) => true,
      );
      expect(defines.first.name, 'foo');
      expect(defines.first.expression, 'bar');
    });

    test('default accepts an integer priority', () {
      final result = RenPyParser().parse('default 2 count = 0', 'sample.rpy');
      final defaults = result.script.findStatements<RenPyDefaultStatement>(
        (_) => true,
      );
      expect(defaults.first.name, 'count');
      expect(defaults.first.expression, '0');
    });

    test('plain define/default still parse', () {
      final result = RenPyParser().parse('''
define foo = 1
default count = 0
''', 'sample.rpy');
      final defines = result.script.findStatements<RenPyDefineStatement>(
        (_) => true,
      );
      final defaults = result.script.findStatements<RenPyDefaultStatement>(
        (_) => true,
      );
      expect(defines.first.name, 'foo');
      expect(defaults.first.name, 'count');
    });
  });

  group('LOW - python early flag', () {
    test('`python early:` is flagged as init', () {
      final result = RenPyParser().parse('''
python early:
    pass
''', 'sample.rpy');
      final python = result.script.findStatements<RenPyPythonStatement>(
        (_) => true,
      );
      expect(python.first.isInit, isTrue);
    });

    test('plain `python:` is not flagged as init', () {
      final result = RenPyParser().parse('''
python:
    pass
''', 'sample.rpy');
      final python = result.script.findStatements<RenPyPythonStatement>(
        (_) => true,
      );
      expect(python.first.isInit, isFalse);
    });
  });
}
