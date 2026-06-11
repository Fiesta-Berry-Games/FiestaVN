import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  RenPyCameraStatement parseSingle(String source) {
    final result = RenPyParser().parse(source, 'camera.rpy');
    expect(
      result.warnings.where((w) => w.contains('Unknown statement type')),
      isEmpty,
      reason: 'camera must not fall through to a generic statement',
    );
    expect(result.script.statements, hasLength(1));
    return result.script.statements.single as RenPyCameraStatement;
  }

  group('camera statements are structured', () {
    test('bare camera', () {
      final camera = parseSingle('camera\n');
      expect(camera.layer, isNull);
      expect(camera.atExpression, isNull);
      expect(camera.withExpression, isNull);
      expect(camera.body, isEmpty);
      expect(camera.filename, 'camera.rpy');
      expect(camera.linenumber, 1);
    });

    test('camera at <transform>', () {
      final camera = parseSingle('camera at flat\n');
      expect(camera.layer, isNull);
      expect(camera.atExpression, 'flat');
      expect(camera.withExpression, isNull);
      expect(camera.body, isEmpty);
    });

    test('camera <layer>', () {
      final camera = parseSingle('camera bg\n');
      expect(camera.layer, 'bg');
      expect(camera.atExpression, isNull);
      expect(camera.withExpression, isNull);
    });

    test('camera <layer> with <transition>', () {
      final camera = parseSingle('camera bg with ease\n');
      expect(camera.layer, 'bg');
      expect(camera.atExpression, isNull);
      expect(camera.withExpression, 'ease');
    });

    test('camera <layer> at <expr-list> with <transition>', () {
      final camera = parseSingle('camera bg at zoomed, panned with dissolve\n');
      expect(camera.layer, 'bg');
      expect(camera.atExpression, 'zoomed, panned');
      expect(camera.withExpression, 'dissolve');
    });

    test('camera at a call expression keeps the raw expression text', () {
      final camera = parseSingle('camera at Transform(zoom=2.0)\n');
      expect(camera.layer, isNull);
      expect(camera.atExpression, 'Transform(zoom=2.0)');
    });

    test('camera: with an ATL block keeps raw body lines', () {
      final camera = parseSingle('''
camera:
    perspective True
    xpos 0
    linear 1.0 xpos 100
''');
      expect(camera.layer, isNull);
      expect(camera.atExpression, isNull);
      expect(camera.body, [
        'perspective True',
        'xpos 0',
        'linear 1.0 xpos 100',
      ]);
    });

    test('camera <layer> at <expr>: with an ATL block', () {
      final camera = parseSingle('''
camera bg at zoomed:
    rotate 45
    pause 0.5
    repeat
''');
      expect(camera.layer, 'bg');
      expect(camera.atExpression, 'zoomed');
      expect(camera.withExpression, isNull);
      expect(camera.body, ['rotate 45', 'pause 0.5', 'repeat']);
    });

    test('nested ATL body lines keep relative indentation', () {
      final camera = parseSingle('''
camera:
    parallel:
        xpos 100
    parallel:
        ypos 50
''');
      expect(camera.body, [
        'parallel:',
        '    xpos 100',
        'parallel:',
        '    ypos 50',
      ]);
    });

    test('camera nested inside a label block', () {
      final result = RenPyParser().parse('''
label start:
    camera at flat
    "Flattened."
''', 'camera.rpy');
      expect(result.warnings, isEmpty);
      final label = result.script.statements.single as RenPyLabelStatement;
      expect(label.block, hasLength(2));
      final camera = label.block[0] as RenPyCameraStatement;
      expect(camera.atExpression, 'flat');
      expect(label.block[1], isA<RenPySayStatement>());
    });

    test('a statement after a camera ATL block still parses', () {
      final result = RenPyParser().parse('''
camera bg at zoomed:
    rotate 45

define after = 1
''', 'camera.rpy');
      expect(result.warnings, isEmpty);
      expect(result.script.statements, hasLength(2));
      expect(result.script.statements[0], isA<RenPyCameraStatement>());
      expect(result.script.statements[1], isA<RenPyDefineStatement>());
    });
  });
}
