import 'dart:io';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

RenPyParseResult _parse(String source) =>
    RenPyParser().parse(source, 'screen_test.rpy');

RenPyScreenStatement _screen(RenPyParseResult result) =>
    result.script.findStatements<RenPyScreenStatement>((_) => true).first;

RenPyStyleStatement _style(RenPyParseResult result, String name) =>
    result.script
        .findStatements<RenPyStyleStatement>((s) => s.style?.name == name)
        .first;

RenPyTransformStatement _transform(RenPyParseResult result) =>
    result.script.findStatements<RenPyTransformStatement>((_) => true).first;

RenPyScreenNode? _findNode(
  List<RenPyScreenNode> nodes,
  bool Function(RenPyScreenNode) predicate,
) {
  for (final node in nodes) {
    if (predicate(node)) return node;
    final inChildren = _findNode(node.children, predicate);
    if (inChildren != null) return inChildren;
    for (final branch in node.branches) {
      final inBranch = _findNode(branch.children, predicate);
      if (inBranch != null) return inBranch;
    }
  }
  return null;
}

void main() {
  group('screen body', () {
    test('parses a window/text structure with positional and properties', () {
      final result = _parse('''
screen say(who, what):
    window:
        id "window"
        text what id "what"
''');
      final screen = _screen(result);
      expect(screen.signature, 'say(who, what)');

      final window = screen.children.single;
      expect(window.kind, 'window');
      expect(window.nodeKind, RenPyScreenNodeKind.displayable);
      expect(window.properties['id'], '"window"');

      final text = _findNode(window.children, (n) => n.kind == 'text')!;
      expect(text.positionalArgs, ['what']);
      expect(text.properties['id'], '"what"');
    });

    test('parses a textbutton with an action property and a text child', () {
      final result = _parse('''
screen m():
    textbutton _("Back") action Rollback():
        text "label"
''');
      final button =
          _findNode(_screen(result).children, (n) => n.kind == 'textbutton')!;
      expect(button.positionalArgs, ['_("Back")']);
      expect(button.properties['action'], 'Rollback()');
      final text = _findNode(button.children, (n) => n.kind == 'text')!;
      expect(text.positionalArgs, ['"label"']);
    });

    test('parses an imagebutton with idle/hover/action properties', () {
      final result = _parse('''
screen m():
    imagebutton idle "a.png" hover "b.png" action Quit()
''');
      final button =
          _findNode(_screen(result).children, (n) => n.kind == 'imagebutton')!;
      expect(button.properties['idle'], '"a.png"');
      expect(button.properties['hover'], '"b.png"');
      expect(button.properties['action'], 'Quit()');
    });

    test('parses for and if inside a screen', () {
      final result = _parse('''
screen m():
    vbox:
        for i in items:
            textbutton i.caption action i.action
        if show_extra:
            text "extra"
        else:
            null
''');
      final forNode =
          _findNode(
            _screen(result).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.forLoop,
          )!;
      expect(forNode.forTarget, 'i');
      expect(forNode.forIterable, 'items');
      expect(forNode.children.single.kind, 'textbutton');

      final ifNode =
          _findNode(
            _screen(result).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.ifChain,
          )!;
      expect(ifNode.branches, hasLength(2));
      expect(ifNode.branches.first.condition, 'show_extra');
      expect(ifNode.branches.last.condition, 'True');
    });

    test('parses a use reference', () {
      final result = _parse('''
screen m():
    use navigation
''');
      final use =
          _findNode(
            _screen(result).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.use,
          )!;
      expect(use.positionalArgs, ['navigation']);
    });

    test('parses transclude and has layout statements', () {
      final result = _parse('''
screen m():
    button:
        action Foo()
        has vbox
    transclude
''');
      final has =
          _findNode(
            _screen(result).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.has,
          )!;
      expect(has.positionalArgs, ['vbox']);
      final transclude = _findNode(
        _screen(result).children,
        (n) => n.nodeKind == RenPyScreenNodeKind.transclude,
      );
      expect(transclude, isNotNull);
    });

    test('parses \$ and python: inside a screen', () {
      final result = _parse('''
screen m():
    \$ slot = i + 1
    python:
        x = 1
        y = 2
''');
      final dollar =
          _findNode(
            _screen(result).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.python,
          )!;
      expect(dollar.pythonCode, 'slot = i + 1');
      final block =
          _findNode(
            _screen(result).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.pythonBlock,
          )!;
      expect(block.pythonCode, 'x = 1\ny = 2');
    });

    test('parses an on event handler inside a screen', () {
      final result = _parse('''
screen m():
    on "show" action Show("other")
''');
      // `on` without a trailing colon is a property form; with a colon it is a
      // block. Exercise the block form here.
      final result2 = _parse('''
screen m():
    on "show":
        timer 0.5 action Hide()
''');
      expect(result.warnings, isEmpty);
      final on =
          _findNode(
            _screen(result2).children,
            (n) => n.nodeKind == RenPyScreenNodeKind.on,
          )!;
      expect(on.event, '"show"');
      expect(on.children.single.kind, 'timer');
    });

    test('parses bare layout properties like xalign and spacing', () {
      final result = _parse('''
screen m():
    vbox:
        spacing 10
        xalign 0.5
''');
      final vbox = _screen(result).children.single;
      expect(vbox.properties['spacing'], '10');
      expect(vbox.properties['xalign'], '0.5');
    });

    test('parses style_prefix as a keyword statement with its value', () {
      final result = _parse('''
screen m():
    style_prefix "input"
''');
      final node =
          _findNode(
            _screen(result).children,
            (n) => n.keyword == 'style_prefix',
          )!;
      expect(node.nodeKind, RenPyScreenNodeKind.keyword);
      expect(node.value, '"input"');
      expect(node.properties, isEmpty);
    });

    test('parses zorder and tag keyword statements with values', () {
      final result = _parse('''
screen m():
    tag menu
    zorder 100
''');
      final tag =
          _findNode(_screen(result).children, (n) => n.keyword == 'tag')!;
      expect(tag.nodeKind, RenPyScreenNodeKind.keyword);
      expect(tag.value, 'menu');
      final zorder =
          _findNode(_screen(result).children, (n) => n.keyword == 'zorder')!;
      expect(zorder.value, '100');
    });

    test('parses modal/predict/variant keyword statements with values', () {
      final result = _parse('''
screen m():
    modal True
    predict False
    variant "touch"
''');
      final modal =
          _findNode(_screen(result).children, (n) => n.keyword == 'modal')!;
      expect(modal.value, 'True');
      final predict =
          _findNode(_screen(result).children, (n) => n.keyword == 'predict')!;
      expect(predict.value, 'False');
      final variant =
          _findNode(_screen(result).children, (n) => n.keyword == 'variant')!;
      expect(variant.value, '"touch"');
    });

    test('parses showif as a keyword statement with a body', () {
      final result = _parse('''
screen m():
    showif ctc:
        add ctc
''');
      final showif =
          _findNode(_screen(result).children, (n) => n.keyword == 'showif')!;
      expect(showif.value, 'ctc');
      expect(showif.children.single.kind, 'add');
    });

    test('captures grid positional dimensions (dotted expressions)', () {
      final result = _parse('''
screen m():
    grid gui.file_slot_cols gui.file_slot_rows:
        null
''');
      final grid =
          _findNode(_screen(result).children, (n) => n.kind == 'grid')!;
      expect(grid.positionalArgs, ['gui.file_slot_cols', 'gui.file_slot_rows']);
      expect(grid.properties.containsKey('gui.file_slot_cols'), isFalse);
    });

    test('folds a bare property inside an if branch into the owner', () {
      final result = _parse('''
screen m():
    label who:
        style "history_name"
        if cond:
            text_color args["color"]
''');
      final label =
          _findNode(_screen(result).children, (n) => n.kind == 'label')!;
      expect(label.properties['text_color'], 'args["color"]');
      // The bare property must not have leaked out as a displayable.
      expect(_findNode(label.children, (n) => n.kind == 'text_color'), isNull);
    });
  });

  group('style body', () {
    test('parses style name, is parent, and properties', () {
      final result = _parse('''
style say_dialogue is default:
    xalign 0.5
    color "#fff"
''');
      final style = _style(result, 'say_dialogue').style!;
      expect(style.name, 'say_dialogue');
      expect(style.parent, 'default');
      expect(style.properties['xalign'], '0.5');
      expect(style.properties['color'], '"#fff"');
    });

    test('parses single-line style x is y', () {
      final result = _parse('style window is default');
      final style = _style(result, 'window').style!;
      expect(style.name, 'window');
      expect(style.parent, 'default');
      expect(style.properties, isEmpty);
    });

    test('keeps bracketed property values intact', () {
      final result = _parse('''
style namebox:
    background Frame("g.png", gui.borders, tile=True)
''');
      final style = _style(result, 'namebox').style!;
      expect(style.parent, isNull);
      expect(
        style.properties['background'],
        'Frame("g.png", gui.borders, tile=True)',
      );
    });
  });

  group('ATL / transform body', () {
    test('parses property assignment, interpolation, pause and repeat', () {
      final result = _parse('''
transform notify_appear:
    alpha 0.0
    on appear:
        linear .25 alpha 1.0
    block:
        linear .2 alpha 0.5
        pause .2
        repeat
''');
      final atl = _transform(result).atl;
      expect(atl, isNotEmpty);

      final prop = atl.first;
      expect(prop.nodeKind, RenPyAtlNodeKind.property);
      expect(prop.properties['alpha'], '0.0');

      final on = atl.firstWhere((n) => n.nodeKind == RenPyAtlNodeKind.on);
      expect(on.event, 'appear');
      final interp = on.children.single;
      expect(interp.nodeKind, RenPyAtlNodeKind.interpolation);
      expect(interp.warper, 'linear');
      expect(interp.duration, '.25');
      expect(interp.properties['alpha'], '1.0');

      final block = atl.firstWhere((n) => n.nodeKind == RenPyAtlNodeKind.block);
      expect(
        block.children.any((n) => n.nodeKind == RenPyAtlNodeKind.pause),
        isTrue,
      );
      expect(
        block.children.any((n) => n.nodeKind == RenPyAtlNodeKind.repeat),
        isTrue,
      );
    });

    test('parses repeat with a count and parallel/choice blocks', () {
      final result = _parse('''
transform t():
    parallel:
        xpos 0.5
    choice 0.5:
        ypos 1.0
    repeat 3
''');
      final atl = _transform(result).atl;
      expect(atl.any((n) => n.nodeKind == RenPyAtlNodeKind.parallel), isTrue);
      final choice = atl.firstWhere(
        (n) => n.nodeKind == RenPyAtlNodeKind.choice,
      );
      expect(choice.duration, '0.5');
      final repeat = atl.firstWhere(
        (n) => n.nodeKind == RenPyAtlNodeKind.repeat,
      );
      expect(repeat.repeatCount, '3');
    });

    test('back-compat: raw body lines are still captured', () {
      final result = _parse('''
transform t():
    xpos 0.5
    linear 1.0 alpha 1.0
''');
      final transform = _transform(result);
      expect(transform.body, isNotEmpty);
      expect(transform.atl, isNotEmpty);
    });
  });

  group('GUI template validation', () {
    final screensFile = File('/tmp/screens.rpy');
    final guiFile = File('/tmp/gui.rpy');

    test(
      'standard screens.rpy parses with structured bodies and no new errors',
      () {
        if (!screensFile.existsSync()) {
          markTestSkipped('screens.rpy not downloaded to /tmp');
          return;
        }
        final result = _parse(screensFile.readAsStringSync());

        // No fatal parse errors surfaced as warnings about indentation or
        // bracket mismatch (the zero-regression assertion).
        final fatal = result.warnings.where(
          (w) =>
              w.contains('Indentation') ||
              w.contains('bracket') ||
              w.contains('Unexpected error'),
        );
        expect(fatal, isEmpty, reason: fatal.join('\n'));

        final screens = result.script.findStatements<RenPyScreenStatement>(
          (_) => true,
        );
        expect(screens, isNotEmpty);

        // The say screen contains a window with a text child.
        final say = screens.firstWhere((s) => s.signature.startsWith('say('));
        final window = _findNode(say.children, (n) => n.kind == 'window')!;
        expect(_findNode(window.children, (n) => n.kind == 'text'), isNotNull);

        // A textbutton with an action somewhere in the template.
        final textbutton = screens
            .map(
              (s) => _findNode(
                s.children,
                (n) =>
                    n.kind == 'textbutton' &&
                    n.properties.containsKey('action'),
              ),
            )
            .firstWhere((n) => n != null);
        expect(textbutton, isNotNull);

        // A `for` and an `if` appear inside screens.
        final forNode = screens
            .map(
              (s) => _findNode(
                s.children,
                (n) => n.nodeKind == RenPyScreenNodeKind.forLoop,
              ),
            )
            .firstWhere((n) => n != null, orElse: () => null);
        expect(forNode, isNotNull);
        final ifNode = screens
            .map(
              (s) => _findNode(
                s.children,
                (n) => n.nodeKind == RenPyScreenNodeKind.ifChain,
              ),
            )
            .firstWhere((n) => n != null, orElse: () => null);
        expect(ifNode, isNotNull);

        // A `use` reference appears.
        final useNode = screens
            .map(
              (s) => _findNode(
                s.children,
                (n) => n.nodeKind == RenPyScreenNodeKind.use,
              ),
            )
            .firstWhere((n) => n != null, orElse: () => null);
        expect(useNode, isNotNull);

        // A `style ... is ...` with properties.
        final styles = result.script.findStatements<RenPyStyleStatement>(
          (_) => true,
        );
        final inheritedStyle = styles.firstWhere(
          (s) => s.style?.parent != null,
        );
        expect(inheritedStyle.style!.parent, isNotNull);
        final styledWithProps = styles.firstWhere(
          (s) => (s.style?.properties.isNotEmpty ?? false),
        );
        expect(styledWithProps.style!.properties, isNotEmpty);

        // A transform/ATL with a linear, pause, and repeat.
        final transforms = result.script
            .findStatements<RenPyTransformStatement>((_) => true);
        expect(transforms, isNotEmpty);

        bool hasAtlKind(RenPyAtlNodeKind kind) {
          bool walk(List<RenPyAtlNode> nodes) {
            for (final node in nodes) {
              if (node.nodeKind == kind) return true;
              if (walk(node.children)) return true;
            }
            return false;
          }

          return transforms.any((t) => walk(t.atl));
        }

        bool hasWarper(String warper) {
          bool walk(List<RenPyAtlNode> nodes) {
            for (final node in nodes) {
              if (node.warper == warper) return true;
              if (walk(node.children)) return true;
            }
            return false;
          }

          return transforms.any((t) => walk(t.atl));
        }

        expect(hasWarper('linear'), isTrue);
        expect(hasAtlKind(RenPyAtlNodeKind.pause), isTrue);
        expect(hasAtlKind(RenPyAtlNodeKind.repeat), isTrue);
      },
    );

    test('standard gui.rpy parses with no fatal errors', () {
      if (!guiFile.existsSync()) {
        markTestSkipped('gui.rpy not downloaded to /tmp');
        return;
      }
      final result = _parse(guiFile.readAsStringSync());
      final fatal = result.warnings.where(
        (w) =>
            w.contains('Indentation') ||
            w.contains('bracket') ||
            w.contains('Unexpected error'),
      );
      expect(fatal, isEmpty, reason: fatal.join('\n'));
    });
  });
}
