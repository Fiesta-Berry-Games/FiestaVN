import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// `dict.update(...)` must work when the receiver is a reified map such as a
/// `**kwargs` value (`Map<String, Object?>`). The previous `addAll(.cast())`
/// threw a `CastMap` subtype error there, which skipped LearnToCodeRPG's
/// `DynamicBlink.__init__` (`kwargs.update({...})`) and the whole blink-image
/// `for` loop that constructs it.
void main() {
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  test('update on a **kwargs map with a dict literal', () {
    final s = scope();
    executor.execute('''
def fn(**kwargs):
    kwargs.update({'k': 1})
    return kwargs
result = fn()
''', s);
    expect(s.read('result'), {'k': 1});
  });

  test('update on a **kwargs map merges with the passed kwargs', () {
    final s = scope();
    executor.execute('''
def fn(**kwargs):
    extra = {'a': 1}
    kwargs.update(extra)
    return kwargs
result = fn(x=9)
''', s);
    expect(s.read('result'), {'x': 9, 'a': 1});
  });

  test('update on an ordinary dict still works (no regression)', () {
    final s = scope();
    executor.execute("d = {'x': 1}\nd.update({'y': 2})", s);
    expect(s.read('d'), {'x': 1, 'y': 2});
  });

  test('update accepts an iterable of key/value pairs', () {
    final s = scope();
    executor.execute("d = {}\nd.update([('a', 1), ('b', 2)])", s);
    expect(s.read('d'), {'a': 1, 'b': 2});
  });

  test('a DynamicBlink-style class with kwargs.update registers and builds', () {
    final s = scope();
    executor.execute('''
class DynamicBlink(renpy.display.layout.DynamicDisplayable):
    def __init__(self, *args, **kwargs):
        self.current_image = args[0]
        kwargs.update({'_predict_function': self.predict_images})
        self.kw = kwargs
    def predict_images(self):
        return self.current_image
charas = ['alice', 'bob']
made = []
for chara in charas:
    made.append(DynamicBlink(chara + '_open', chara + '_closed'))
''', s);
    final made = s.read('made') as List;
    expect(made.length, 2);
  });
}
