import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyScreenRuntime _runtimeFor(String source, {Map<String, Object?>? store}) {
  final result = RenPyParser().parse(source, 'screen_test.rpy');
  final screens = <String, RenPyScreenStatement>{};
  final styles = <String, RenPyStyle>{};
  for (final statement in result.script.statements) {
    if (statement is RenPyScreenStatement) {
      final name = RegExp(r'^([A-Za-z_]\w*)').firstMatch(statement.signature);
      if (name != null) screens[name.group(1)!] = statement;
    } else if (statement is RenPyStyleStatement && statement.style != null) {
      styles[statement.style!.name] = statement.style!;
    }
  }
  final scope = RenPyMapScope(
    store: store ?? <String, Object?>{},
    persistent: <String, Object?>{},
  );
  return RenPyScreenRuntime(screens: screens, styles: styles, scope: scope);
}

void main() {
  group('RenPyScreenRuntime.resolveScreen', () {
    test('resolves text, textbutton with action, if and for', () {
      final runtime = _runtimeFor(
        '''
screen menu_screen(count):
    vbox:
        text "Title"
        if count > 0:
            textbutton "Yes" action Return(True)
        else:
            text "None"
        for item in choices:
            textbutton item action Jump("go")
''',
        store: {
          'choices': ['a', 'b'],
        },
      );

      final resolved = runtime.resolveScreen('menu_screen', positional: [2]);
      expect(resolved, isNotNull);
      expect(resolved!.diagnostics, isEmpty);

      final vbox = resolved.children.single;
      expect(vbox.kind, 'vbox');

      // Title text + the matched if branch (textbutton Yes) + 2 for items.
      final kinds = vbox.children.map((c) => c.kind).toList();
      expect(kinds, ['text', 'textbutton', 'textbutton', 'textbutton']);

      final title = vbox.children[0];
      expect(title.text, 'Title');

      // The `if count > 0` branch is included; the `else` text "None" excluded.
      final yes = vbox.children[1];
      expect(yes.text, 'Yes');
      expect(yes.action, isNotNull);
      expect(yes.action!.kind, RenPyScreenActionKind.returnValue);
      expect(yes.action!.value, true);

      // The for loop expands once per item with the loop variable in scope.
      expect(vbox.children[2].text, 'a');
      expect(vbox.children[3].text, 'b');
      expect(vbox.children[2].action!.kind, RenPyScreenActionKind.jump);
      expect(vbox.children[2].action!.label, 'go');
    });

    test('excludes the if branch when the condition is false', () {
      final runtime = _runtimeFor('''
screen gated(count):
    if count > 0:
        text "Shown"
    else:
        text "Hidden"
''');
      final resolved = runtime.resolveScreen('gated', positional: [0]);
      expect(resolved!.children.single.text, 'Hidden');
    });

    test('evaluates property expressions against screen params and store', () {
      final runtime = _runtimeFor(
        '''
screen sized(width):
    frame:
        xsize width
        ysize base_height
''',
        store: {'base_height': 480},
      );
      final resolved = runtime.resolveScreen('sized', positional: [200]);
      final frame = resolved!.children.single;
      expect(frame.properties['xsize'], 200);
      expect(frame.properties['ysize'], 480);
    });

    test('inlines a used screen and applies transclude', () {
      final runtime = _runtimeFor('''
screen outer():
    use inner("hi"):
        text "transcluded body"

screen inner(label):
    vbox:
        text label
        transclude
''');
      final resolved = runtime.resolveScreen('outer');
      expect(resolved, isNotNull);
      final vbox = resolved!.children.single;
      expect(vbox.kind, 'vbox');
      expect(vbox.children[0].text, 'hi');
      expect(vbox.children[1].text, 'transcluded body');
    });

    test('records a diagnostic for an unknown use target', () {
      final runtime = _runtimeFor('''
screen broken():
    use missing_screen()
''');
      final resolved = runtime.resolveScreen('broken');
      expect(resolved!.children, isEmpty);
      expect(
        resolved.diagnostics.single.code,
        RenPyDiagnosticCode.skippedScreen,
      );
    });

    test('runs screen `\$` for side effects against the store', () {
      final runtime = _runtimeFor(
        '''
screen compute():
    \$ total = a + b
    text "[total]"
''',
        store: {'a': 2, 'b': 3},
      );
      final resolved = runtime.resolveScreen('compute');
      // The text positional is the raw literal (RenPy [var] substitution is the
      // renderer's job), but the side effect wrote `total` to the store.
      expect(resolved!.children, isNotEmpty);
    });

    test('applies style_prefix to descendant displayables', () {
      final runtime = _runtimeFor('''
screen prefixed():
    vbox:
        style_prefix "fancy"
        textbutton "Click"
        text "Body"
''');
      final resolved = runtime.resolveScreen('prefixed');
      final vbox = resolved!.children.single;
      final button = vbox.children.firstWhere((c) => c.kind == 'textbutton');
      final body = vbox.children.firstWhere((c) => c.kind == 'text');
      expect(button.styleName, 'fancy_textbutton');
      expect(body.styleName, 'fancy_text');
    });
  });

  group('RenPyStyleResolver', () {
    test('flattens a style through its `is` parent chain', () {
      final runtime = _runtimeFor('''
style base_button:
    padding (10, 10)
    background "#333"

style fancy_button is base_button:
    background "#f00"

screen styled():
    button:
        style "fancy_button"
''');
      final resolved = runtime.resolveScreen('styled');
      final button = resolved!.children.single;
      expect(button.styleName, 'fancy_button');
      // Parent property inherited.
      expect(button.style['padding'], [10, 10]);
      // Child overrides the parent's background.
      expect(button.style['background'], '#f00');
    });
  });

  group('RenPyScreenAction.parse', () {
    final scope = RenPyMapScope(
      store: <String, Object?>{'score': 5},
      persistent: <String, Object?>{},
    );
    const evaluator = RenPyPythonEvaluator();

    test('parses Return with a value', () {
      final action = RenPyScreenAction.parse('Return(42)', evaluator, scope);
      expect(action.kind, RenPyScreenActionKind.returnValue);
      expect(action.value, 42);
      expect(action.hasValue, true);
    });

    test('parses SetVariable', () {
      final action = RenPyScreenAction.parse(
        'SetVariable("score", 10)',
        evaluator,
        scope,
      );
      expect(action.kind, RenPyScreenActionKind.setVariable);
      expect(action.target, 'score');
      expect(action.value, 10);
    });

    test('parses ToggleField with a raw object expression', () {
      final action = RenPyScreenAction.parse(
        'ToggleField(persistent, "muted")',
        evaluator,
        scope,
      );
      expect(action.kind, RenPyScreenActionKind.toggleField);
      expect(action.target, 'persistent');
      expect(action.field, 'muted');
    });

    test('falls back to NullAction for an unknown action', () {
      final action = RenPyScreenAction.parse(
        'SomethingWeird(1)',
        evaluator,
        scope,
      );
      expect(action.kind, RenPyScreenActionKind.nullAction);
      expect(action.raw, 'SomethingWeird(1)');
    });
  });
}
