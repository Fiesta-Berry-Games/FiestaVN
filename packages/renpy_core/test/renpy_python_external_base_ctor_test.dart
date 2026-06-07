import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for constructing user-defined classes that inherit from opaque
/// external bases (e.g. `renpy.character.ADVCharacter`).
///
/// When a class has a base but no explicit `__init__`, keyword arguments
/// should be stored as instance attributes and no error should be raised.
/// This mirrors how `my_adv = MyADVCharacter(None, who_prefix='', ...)` works.
void main() {
  const executor = RenPyPythonExecutor();

  Map<String, Object?> run(String source) {
    final store = <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: store, persistent: <String, Object?>{}),
    );
    return store;
  }

  group('class inheriting from external base - keyword constructor', () {
    test('subclass of opaque base can be instantiated with kwargs', () {
      final store = run('''
class MyChar(renpy.character.ADVCharacter):
    pass

c = MyChar(None, who_prefix='', who_suffix='')
''');
      expect(store['c'], isNotNull);
    });

    test('kwargs are stored as instance attributes', () {
      final store = run('''
class Cfg(renpy.character.ADVCharacter):
    pass

c = Cfg(None, who_prefix='[', who_suffix=']', screen='say')
prefix = c.who_prefix
screen = c.screen
''');
      expect(store['prefix'], '[');
      expect(store['screen'], 'say');
    });

    test('method defined in subclass is callable after opaque-base ctor', () {
      final store = run('''
class MyChar(renpy.character.ADVCharacter):
    def get_prefix(self):
        return self.who_prefix

c = MyChar(None, who_prefix='>>>')
result = c.get_prefix()
''');
      expect(store['result'], '>>>');
    });

    test('MyADVCharacter with renpy function kwargs instantiates successfully',
        () {
      final store = run('''
class MyADVCharacter(renpy.character.ADVCharacter):
    def __call__(self, what, interact=True, **kwargs):
        return None

my_adv = MyADVCharacter(
    None,
    who_prefix='',
    who_suffix='',
    what_prefix='',
    what_suffix='',
    show_function=renpy.show_display_say,
    predict_function=renpy.predict_show_display_say,
    condition=None,
    dynamic=False,
    kind=False
)
''');
      expect(store['my_adv'], isNotNull);
    });
  });

  group('class with explicit __init__ still works normally', () {
    test('explicit __init__ takes precedence over base-ctor fallback', () {
      final store = run('''
class Widget(renpy.display.layout.DynamicDisplayable):
    def __init__(self, label):
        self.label = label

w = Widget("hello")
lbl = w.label
''');
      expect(store['lbl'], 'hello');
    });
  });

  group('plain class (no base) with args still throws', () {
    test('class with no base and no __init__ rejects args', () {
      expect(
        () => run('class Bare:\n    pass\nx = Bare(1, 2)'),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });
}
