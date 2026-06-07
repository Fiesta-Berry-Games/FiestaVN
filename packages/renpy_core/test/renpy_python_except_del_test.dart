/// Unit tests for: tuple except, del no-op, stub-error
/// catch, renpy.scene, renpy.display.get_info, preferences namespace,
/// and store method no-op via _StoreProxy.
library;

import 'package:renpy_core/src/renpy_python.dart';
import 'package:test/test.dart';

const _executor = RenPyPythonExecutor();
const _evaluator = RenPyPythonEvaluator();

RenPyMapScope _scope([Map<String, Object?>? store]) =>
    RenPyMapScope(store: store ?? {}, persistent: {});

Map<String, Object?> _run(String code, [Map<String, Object?>? store]) {
  final s = store ?? <String, Object?>{};
  _executor.execute(code, _scope(s));
  return s;
}

Object? _eval(String expr, [Map<String, Object?>? store]) =>
    _evaluator.evaluate(expr, _scope(store));

void main() {
  // -- del as no-op ---------------------------------------------------------
  group('del statement is a no-op', () {
    test('del at top level does not throw', () {
      expect(() => _run('x = 1\ndel x\n'), returnsNormally);
    });

    test('del inside if body does not prevent def from registering', () {
      const code = 'def clean_list(lst):\n'
          '    if len(lst) > 5:\n'
          '        item = lst.pop(0)\n'
          '        del item\n'
          '    return lst\n'
          'result = clean_list([1,2,3,4,5,6])\n';
      final s = _run(code);
      expect(s['result'], [2, 3, 4, 5, 6]);
    });
  });

  // -- tuple except ---------------------------------------------------------
  group('tuple exception types in except clause', () {
    test('except (TypeError, ValueError) catches the right exception', () {
      const code = 'caught = False\n'
          'try:\n'
          '    raise TypeError("oops")\n'
          'except (TypeError, ValueError) as e:\n'
          '    caught = True\n';
      final s = _run(code);
      expect(s['caught'], true);
    });

    test('except (TypeError, ValueError) does not catch typed AttributeError', () {
      // A typed exception (AttributeError) that is not in the tuple re-raises
      // and surfaces as an uncaught RenPyPythonError.
      const code = 'caught = False\n'
          'try:\n'
          '    raise AttributeError("oops")\n'
          'except (TypeError, ValueError):\n'
          '    caught = True\n';
      expect(() => _run(code), throwsA(isA<RenPyPythonError>()));
    });

    test('bare except (no types) still catches anything', () {
      const code = 'caught = False\n'
          'try:\n'
          '    raise ValueError("x")\n'
          'except:\n'
          '    caught = True\n';
      final s = _run(code);
      expect(s['caught'], true);
    });

    test('dotted except type (store.SomeError) uses last component', () {
      // Should not throw when parsing dotted exception names.
      const code = 'caught = False\n'
          'try:\n'
          '    x = 1\n'
          'except store.KeyError:\n'
          '    caught = True\n';
      expect(() => _run(code), returnsNormally);
    });
  });

  // -- stub errors caught by named except -----------------------------------
  group('RenPy stub errors are caught by named except', () {
    test('stub error inside try is caught by a named except ValueError', () {
      // config.keymap is None; config.keymap[...].remove(...) raises a stub
      // error. The except ValueError: pass should silence it.
      const code = 'config.keymap = {"game_menu": []}\n'
          'try:\n'
          '    config.keymap["game_menu"].remove("mouseup_3")\n'
          'except ValueError:\n'
          '    pass\n';
      expect(() => _run(code), returnsNormally);
    });

    test('stub error in try with bare except is caught', () {
      const code = 'result = "before"\n'
          'try:\n'
          '    undefined_function()\n'
          'except:\n'
          '    result = "caught"\n';
      final s = _run(code);
      expect(s['result'], 'caught');
    });
  });

  // -- renpy.scene ----------------------------------------------------------
  group('renpy.scene is a no-op', () {
    test('renpy.scene() returns null without error', () {
      expect(_eval('renpy.scene()'), isNull);
    });

    test('renpy.scene() with layer kwarg returns null', () {
      expect(_eval('renpy.scene(layer="master")'), isNull);
    });
  });

  // -- renpy.display.get_info -----------------------------------------------
  group('renpy.display.get_info returns stub with screen dimensions', () {
    test('get_info() returns an object with current_w and current_h', () {
      const code = 'inf = renpy.display.get_info()\n'
          'w = inf.current_w\n'
          'h = inf.current_h\n';
      final s = _run(code);
      expect(s['w'], isA<num>());
      expect(s['h'], isA<num>());
    });

    test('get_info() uses config.screen_width/height when set', () {
      const code = 'inf = renpy.display.get_info()\n'
          'ww = inf.current_w\n';
      final scope = RenPyMapScope(store: {}, persistent: {}, config: {'screen_width': 750});
      _executor.execute(code, scope);
      expect(scope.read('ww'), 750);
    });
  });

  // -- preferences namespace ------------------------------------------------
  group('preferences.x = y works as a scoped write', () {
    test('preferences.afm_enable = True does not throw', () {
      expect(() => _run('preferences.afm_enable = True\n'), returnsNormally);
    });

    test('preferences.afm_enable read back after write', () {
      final s = _run('preferences.afm_enable = False\n');
      expect(s['preferences.afm_enable'], false);
    });

    test('preferences.text_speed read returns null when unset', () {
      expect(_eval('preferences.text_speed'), isNull);
    });
  });

  // -- renpy.has_image ------------------------------------------------------
  group('renpy.has_image returns false headless', () {
    test('renpy.has_image("bg x") returns false', () {
      expect(_eval('renpy.has_image("bg morning")'), false);
    });
  });

  // -- store._window_hide() via _StoreProxy ---------------------------------
  group('store.method() on unregistered method is a no-op', () {
    test('store._window_hide() when not defined does not throw', () {
      expect(() => _run('store._window_hide()\n'), returnsNormally);
    });

    test('store._window_hide() when defined as a function calls it', () {
      const code = 'called = False\n'
          'def _window_hide():\n'
          '    global called\n'
          '    called = True\n'
          'store._window_hide()\n';
      final s = _run(code);
      expect(s['called'], true);
    });
  });
}
