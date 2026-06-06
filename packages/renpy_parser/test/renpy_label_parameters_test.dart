import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

/// Parameterized labels `label name(a, b=expr):` (Ren'Py). Previously the label
/// regex required `:` right after the name, so `label start():` failed to parse
/// - dropping the entry point of games like `mysterious-messenger` (194 such
/// labels).
void main() {
  RenPyLabelStatement? labelNamed(String source, String name) {
    final script = RenPyParser().parse(source, 'labels.rpy').script;
    for (final s in script.statements) {
      if (s is RenPyLabelStatement && s.name == name) return s;
    }
    return null;
  }

  test('a zero-parameter label registers under its bare name', () {
    final label = labelNamed('label start():\n    "hi"\n', 'start');
    expect(label, isNotNull);
    expect(label!.parameters, isEmpty);
  });

  test('a plain label still parses (no regression)', () {
    final label = labelNamed('label intro:\n    "hi"\n', 'intro');
    expect(label, isNotNull);
    expect(label!.parameters, isEmpty);
  });

  test('parameters with and without defaults are captured', () {
    final label = labelNamed('label day(n, mood="happy"):\n    "hi"\n', 'day');
    expect(label, isNotNull);
    expect(label!.parameters.map((p) => p.name), ['n', 'mood']);
    expect(label.parameters[0].defaultExpression, isNull);
    expect(label.parameters[1].defaultExpression, '"happy"');
  });

  test('a default expression containing a comma is not split', () {
    final label = labelNamed('label f(x=foo(1, 2)):\n    "hi"\n', 'f');
    expect(label, isNotNull);
    expect(label!.parameters, hasLength(1));
    expect(label.parameters[0].name, 'x');
    expect(label.parameters[0].defaultExpression, 'foo(1, 2)');
  });

  test('varargs parameters are preserved with their stars', () {
    final label = labelNamed('label g(a, *args, **kwargs):\n    "hi"\n', 'g');
    expect(label, isNotNull);
    expect(label!.parameters.map((p) => p.name), ['a', '*args', '**kwargs']);
  });
}
