import 'dart:io';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/src/renpy_emitter.dart';
import 'package:test/test.dart';

const emitter = RenPyEmitter();
final parser = RenPyParser();

// ---------------------------------------------------------------------------
// Structural signature walker
// ---------------------------------------------------------------------------

/// Flattens [script] into a list of descriptor strings: one entry per
/// statement (depth-prefixed), carrying the runtimeType plus key scalars
/// (label names, say character/text, jump targets, menu choice texts, if
/// branch conditions, ...). Two scripts with equal signatures have the same
/// statement classes in the same order with the same key payloads.
List<String> signatureOf(RenPyScript script) {
  final out = <String>[];
  for (final statement in script.statements) {
    _describe(statement, 0, out);
  }
  return out;
}

void _describeBlock(List<RenPyStatement> block, int depth, List<String> out) {
  for (final statement in block) {
    _describe(statement, depth, out);
  }
}

void _describe(RenPyStatement s, int depth, List<String> out) {
  final pad = '$depth:';
  if (s is RenPyLabelStatement) {
    final params = s.parameters
        .map((p) => '${p.name}=${p.defaultExpression}')
        .join(',');
    out.add('${pad}Label(${s.name})[$params]');
    _describeBlock(s.block, depth + 1, out);
  } else if (s is RenPySayStatement) {
    out.add(
      '${pad}Say(${s.character}|${s.text}'
      '|${s.attributes.join(',')}|${s.temporaryAttributes.join(',')})',
    );
  } else if (s is RenPyMenuStatement) {
    out.add('${pad}Menu(${s.name}|${s.caption}|${s.setVariable})');
    for (final choice in s.items) {
      out.add('${pad}Choice(${choice.text}|${choice.condition})');
      _describeBlock(choice.block, depth + 1, out);
    }
  } else if (s is RenPyJumpStatement) {
    out.add('${pad}Jump(${s.target}|expr=${s.isExpression})');
  } else if (s is RenPyCallStatement) {
    out.add(
      '${pad}Call(${s.isScreen ? 'screen ${s.screenName}(${s.screenArgs})' : s.target}'
      '|expr=${s.isExpression}|args=${s.callArgs})',
    );
  } else if (s is RenPyIfStatement) {
    for (final entry in s.entries) {
      out.add('${pad}IfBranch(${entry.condition})');
      _describeBlock(entry.block, depth + 1, out);
    }
  } else if (s is RenPyWhileStatement) {
    out.add('${pad}While(${s.condition})');
    _describeBlock(s.block, depth + 1, out);
  } else if (s is RenPyForStatement) {
    out.add('${pad}For(${s.variable} in ${s.iterable})');
    _describeBlock(s.block, depth + 1, out);
  } else if (s is RenPyInitStatement) {
    out.add('${pad}Init(${s.priority}|python=${s.isPython})');
    _describeBlock(s.block, depth + 1, out);
  } else if (s is RenPyShowStatement) {
    out.add(
      '${pad}Show(${s.imageName}|${s.displayableText}|${s.atExpression}'
      '|${s.behindExpression}|${s.onLayerExpression}|${s.zOrderExpression}'
      '|${s.withExpression})',
    );
  } else if (s is RenPySceneStatement) {
    out.add(
      '${pad}Scene(${s.imageName}|${s.atExpression}|${s.onLayerExpression}'
      '|${s.zOrderExpression}|${s.withExpression})',
    );
  } else if (s is RenPyHideStatement) {
    out.add(
      '${pad}Hide(${s.imageName}|${s.onLayerExpression}|${s.withExpression})',
    );
  } else if (s is RenPyWithStatement) {
    out.add('${pad}With(${s.transition})');
  } else if (s is RenPyDefineStatement) {
    out.add('${pad}Define(${s.name})');
  } else if (s is RenPyDefaultStatement) {
    out.add('${pad}Default(${s.name})');
  } else if (s is RenPyReturnStatement) {
    out.add('${pad}Return(${s.expression})');
  } else if (s is RenPyPlayStatement) {
    out.add('${pad}Play(${s.channel}|${s.expression})');
  } else if (s is RenPyQueueStatement) {
    out.add('${pad}Queue(${s.channel}|${s.expression})');
  } else if (s is RenPyVoiceStatement) {
    out.add('${pad}Voice(${s.expression})');
  } else if (s is RenPyStopStatement) {
    out.add('${pad}Stop(${s.channel}|${s.fadeout})');
  } else if (s is RenPyPauseStatement) {
    out.add('${pad}Pause(${s.duration})');
  } else if (s is RenPyWindowStatement) {
    out.add('${pad}Window(${s.action.name}|${s.transition})');
  } else if (s is RenPyImageStatement) {
    out.add('${pad}Image(${s.name}|${s.expression}|body=${s.body.length})');
  } else if (s is RenPyInitOffsetStatement) {
    out.add('${pad}InitOffset(${s.offset})');
  } else if (s is RenPyScreenStatement) {
    out.add('${pad}Screen(${s.signature})');
    for (final node in s.children) {
      _describeScreenNode(node, depth + 1, out);
    }
  } else if (s is RenPyStyleStatement) {
    out.add('${pad}Style(${s.declaration})');
  } else if (s is RenPyTransformStatement) {
    out.add('${pad}Transform(${s.signature}|body=${s.body.length})');
  } else if (s is RenPyLayeredImageStatement) {
    out.add('${pad}LayeredImage(${s.name})');
    for (final layer in s.layers) {
      out.add(
        '${pad}Layer(${layer.kind.name}|${layer.group}|${layer.attribute}'
        '|default=${layer.isDefault}|${layer.condition}|${layer.displayable})',
      );
    }
  } else if (s is RenPyGenericStatement) {
    out.add('${pad}Generic(${s.text})');
  } else if (s is RenPyBlockStatement) {
    out.add('$pad${s.runtimeType}');
    _describeBlock(s.block, depth + 1, out);
  } else {
    out.add('$pad${s.runtimeType}');
  }
}

void _describeScreenNode(RenPyScreenNode node, int depth, List<String> out) {
  final keys = node.properties.keys.toList()..sort();
  out.add(
    '$depth:ScreenNode(${node.nodeKind.name}|${node.kind}'
    '|${node.positionalArgs.join(',')}|props=${keys.join(',')}'
    '|${node.keyword}|${node.value}|${node.forTarget}|${node.forIterable})',
  );
  for (final branch in node.branches) {
    out.add('$depth:ScreenBranch(${branch.condition})');
    for (final child in branch.children) {
      _describeScreenNode(child, depth + 1, out);
    }
  }
  for (final child in node.children) {
    _describeScreenNode(child, depth + 1, out);
  }
}

// ---------------------------------------------------------------------------
// Fixpoint helper
// ---------------------------------------------------------------------------

/// Parses [source], emits it, reparses the emission, and emits again.
/// Asserts the two emissions are byte-identical (the emitter is a fixpoint of
/// parse-then-emit) and - unless [compareSignatures] is false (used for the
/// emitter's documented normalizations that change node classes, like
/// `python early:` -> `init python:`) - that the reparsed tree has the same
/// statement types and key scalars in the same order as the original parse.
/// Returns the emitted text.
String expectFixpoint(String source, {bool compareSignatures = true}) {
  final first = parser.parse(source, 'test.rpy');
  final emitted = emitter.emitScript(first.script);
  final second = parser.parse(emitted, 'test.rpy');
  final reEmitted = emitter.emitScript(second.script);
  expect(
    reEmitted,
    equals(emitted),
    reason:
        'emission is not a fixpoint.\n--- first emission ---\n$emitted'
        '\n--- second emission ---\n$reEmitted',
  );
  if (compareSignatures) {
    expect(
      signatureOf(second.script),
      equals(signatureOf(first.script)),
      reason:
          'reparsing the emitted text changed the statement tree.'
          '\n--- emitted ---\n$emitted',
    );
  }
  return emitted;
}

/// Parses [source] and asserts that emitting it produces exactly [expected].
void expectEmits(String source, String expected) {
  final script = parser.parse(source, 'test.rpy').script;
  expect(emitter.emitScript(script), expected);
}

void main() {
  group('fixpoint round-trips per statement type', () {
    test('say: narrator, character, attributes, temporary attributes', () {
      expectFixpoint(r'''
label start:
    "Plain narration."
    e "Hello."
    e happy "Hello!"
    e happy -mad +glasses "Layered."
    e happy @ vhappy "Just this once."
    e @ sad "Bare temporary run."
''');
    });

    test('say: quoted (non-identifier) speakers', () {
      expectFixpoint(r'''
label start:
    "The Narrator" "A quoted speaker."
''');
    });

    test('say: escape sequences survive', () {
      expectFixpoint(r'''
label start:
    "She said \"hi\" to me."
    e "Tab\there and a\nnewline and a backslash \\."
''');
    });

    test('label: plain, parameters, defaults, varargs', () {
      expectFixpoint(r'''
label start:
    return
label chapter(number):
    return
label scene_with(actor="eileen", mood="happy", *args, **kwargs):
    return
''');
    });

    test('menu: anonymous, named, caption, set, conditions', () {
      expectFixpoint(r'''
label start:
    menu:
        "Pick one":
            pass
    menu retry_menu:
        "Which way?"
        set seen_choices
        "Left" if brave:
            jump left_path
        "Right":
            "You went right."
label left_path:
    return
''');
    });

    test('jump and jump expression', () {
      expectFixpoint(r'''
label start:
    jump ending
    jump expression "end_" + "game"
label ending:
    return
''');
    });

    test('call: plain, args, expression, screen', () {
      expectFixpoint(r'''
label start:
    call subroutine
    call subroutine(1, 2)
    call expression "sub" + "routine"
    call screen confirm_screen("Quit?")
    call screen bare_screen
''');
    });

    test('show, scene, hide, with', () {
      expectFixpoint(r'''
label start:
    scene bg room with fade
    scene bg washington at left onlayer master zorder 1 with dissolve
    show eileen happy
    show eileen happy at left behind curtain onlayer master zorder 2 with dissolve
    hide eileen
    hide eileen onlayer master with dissolve
    with fade
''');
    });

    test('show text with and without explicit tag', () {
      expectFixpoint(r'''
label start:
    show text "Chapter One" as title at truecenter with dissolve
    show text "Untagged" at truecenter
''');
    });

    test(r'python: $ one-liner, blocks, and the assignment normalization', () {
      expectFixpoint(r'''
label start:
    $ renpy.pause(0.5)
    $ points += 1
    $ score = 10
    python:
        x = 1
        if x > 0:
            y = 2
''');
    });

    test('python early normalizes to init python (text fixpoint only)', () {
      // The parser keeps only an isInit flag, so `python early:` re-emits as
      // `init python:` and re-parses as an init statement wrapping the python
      // code: the tree class changes once, but the text is already stable.
      expectFixpoint('''
python early:
    foo = 1
''', compareSignatures: false);
    });

    test('init: offset, plain block, priority, python with priority', () {
      expectFixpoint(r'''
init offset = 2
init:
    define inside = 1
init 2:
    define bar = 3
init python:
    foo = 1
init -2 python:
    baz = 2
    def helper():
        return baz
''');
    });

    test('define and default', () {
      expectFixpoint(r'''
define e = Character("Eileen")
define config.name = "The Question"
default points = 0
''');
    });

    test('if / elif / else, nested', () {
      expectFixpoint(r'''
label start:
    if points > 3:
        e "Lots."
    elif points > 1:
        e "Some."
        if nested:
            e "Nested."
        else:
            e "Not nested."
    else:
        e "None."
''');
    });

    test('while, for, break, continue, pass, return', () {
      expectFixpoint(r'''
label start:
    while points < 10:
        $ points += 1
        if points == 5:
            continue
        if points == 9:
            break
    for q in questions:
        e "[q]"
    for i, value in enumerate(items):
        pass
    pass
    return
label scored:
    return points
''');
    });

    test('nvl clear', () {
      expectFixpoint(r'''
label start:
    nvl clear
''');
    });

    test('image: assignment and ATL-body forms', () {
      expectFixpoint(r'''
image eileen happy = "eileen_happy.png"
image movie = Movie(play="oa4_movie.webm")
image moving:
    "eileen_happy.png"
    xpos 0.0
    linear 2.0 xpos 1.0
    repeat
''');
    });

    test('window show/hide/auto with and without transition', () {
      expectFixpoint(r'''
label start:
    window show dissolve
    window show
    window hide
    window auto
''');
    });

    test('pause with and without duration', () {
      expectFixpoint(r'''
label start:
    pause 0.5
    pause
''');
    });

    test('audio: play, queue, voice, voice sustain, stop', () {
      expectFixpoint(r'''
label start:
    play music "theme.ogg"
    play sound "ding.ogg" fadein 0.5
    queue sound "ding.ogg"
    voice "line01.ogg"
    voice sustain
    stop music
    stop music fadeout 1.0
''');
    });

    test('screen: keywords, displayables, if, for, python, use', () {
      expectFixpoint(r'''
screen hello_screen(who):
    tag menu
    modal True
    zorder 100
    vbox:
        spacing 10
        xalign 0.5
        text "Hello [who]!"
        if points > 0:
            text "You have points."
        elif points == 0:
            text "Zero."
        else:
            text "No points."
        for q in questions:
            textbutton q action Return(q)
        $ tally = points + 1
    use other_screen
''');
    });

    test('style: block form with properties', () {
      expectFixpoint(r'''
style say_dialogue is default:
    xalign 0.5
    yalign 1.0
''');
    });

    test('transform with ATL body', () {
      expectFixpoint(r'''
transform slide:
    xpos 0.0
    linear 1.0 xpos 0.5
    pause 0.5
    repeat 3
transform flash(duration=0.5):
    alpha 0.0
    linear duration alpha 1.0
''');
    });

    test('layeredimage: always, groups, bare attributes, conditions', () {
      expectFixpoint(r'''
layeredimage eileen:
    always:
        "eileen_base"
    group outfit:
        attribute dress default:
            "eileen_dress"
        attribute casual:
            "eileen_casual"
    if points > 5:
        "eileen_crown"
''');
    });

    test('generic (unrecognized) statements pass through', () {
      expectFixpoint(r'''
label start:
    camera bg at zoom
''');
    });

    test(r'edge cases: quoted choice text, dotted $, bare scene, nesting', () {
      expectFixpoint(r'''
label start:
    menu:
        "Say \"hi\"":
            menu:
                "Nested":
                    return
    $ config.name = "x"
    scene
style foo is bar
''');
    });

    test('triple-quoted say normalizes to an escaped single-line say', () {
      final emitted = expectFixpoint(
        'label start:\n'
        '    e """line one\nline two"""\n',
      );
      expect(emitted, contains(r'e "line one\nline two"'));
    });

    test('comprehensive snippet covering every statement type', () {
      final first = parser.parse(_comprehensiveSnippet, 'test.rpy');
      expectFixpoint(_comprehensiveSnippet);

      // Sanity-check the corpus really exercises the whole dispatch table.
      final types = <Type>{};
      void walk(List<RenPyStatement> statements) {
        for (final s in statements) {
          types.add(s.runtimeType);
          if (s is RenPyIfStatement) {
            for (final entry in s.entries) {
              walk(entry.block);
            }
          } else if (s is RenPyMenuStatement) {
            for (final choice in s.items) {
              walk(choice.block);
            }
          } else if (s is RenPyBlockStatement) {
            walk(s.block);
          }
        }
      }

      walk(first.script.statements);
      expect(
        types,
        containsAll(<Type>{
          RenPySayStatement,
          RenPyLabelStatement,
          RenPyMenuStatement,
          RenPyJumpStatement,
          RenPyCallStatement,
          RenPyShowStatement,
          RenPySceneStatement,
          RenPyHideStatement,
          RenPyWithStatement,
          RenPyPythonStatement,
          RenPyDefineStatement,
          RenPyDefaultStatement,
          RenPyIfStatement,
          RenPyWhileStatement,
          RenPyForStatement,
          RenPyLoopControlStatement,
          RenPyPassStatement,
          RenPyReturnStatement,
          RenPyNvlStatement,
          RenPyImageStatement,
          RenPyWindowStatement,
          RenPyPauseStatement,
          RenPyPlayStatement,
          RenPyQueueStatement,
          RenPyVoiceStatement,
          RenPyStopStatement,
          RenPyInitOffsetStatement,
          RenPyInitStatement,
          RenPyScreenStatement,
          RenPyStyleStatement,
          RenPyTransformStatement,
          RenPyLayeredImageStatement,
          RenPyGenericStatement,
        }),
      );
    });
  });

  group('real-game fixtures', () {
    const fixtures = [
      '../../apps/renfly_player/assets/games/the_question/game/script.rpy',
      '../../apps/renfly_player/assets/games/3/game/script.rpy',
      '../../apps/renfly_player/assets/games/4/game/script.rpy',
    ];

    for (final path in fixtures) {
      test(path, () {
        final source = File(path).readAsStringSync();
        final first = parser.parse(source, path);
        final originalWarnings = first.warnings.length;

        final emitted = emitter.emitScript(first.script);
        final second = parser.parse(emitted, path);
        final reEmitted = emitter.emitScript(second.script);

        expect(
          reEmitted,
          equals(emitted),
          reason: 'fixture $path emission is not a fixpoint',
        );
        expect(second.script.statements, isNotEmpty);
        expect(
          second.warnings.length,
          lessThanOrEqualTo(originalWarnings),
          reason:
              'reparsing the emission of $path produced new warnings:\n'
              '${second.warnings.join('\n')}',
        );
      });
    }
  });

  group('exact output', () {
    test('say with character, attributes and temporary attributes', () {
      expectEmits(
        'label start:\n'
        '    e happy confident @ vhappy "Hi!"\n',
        'label start:\n'
        '    e happy confident @ vhappy "Hi!"\n',
      );
    });

    test('narrator say with escaped quote in text', () {
      expectEmits(
        'label start:\n'
        '    "She said \\"hi\\" to me."\n',
        'label start:\n'
        '    "She said \\"hi\\" to me."\n',
      );
    });

    test('label with parameters', () {
      expectEmits(
        'label start(chapter=1, *args):\n'
        '    return\n',
        'label start(chapter=1, *args):\n'
        '    return\n',
      );
    });

    test('jump and jump expression', () {
      expectEmits(
        'label start:\n'
        '    jump ending\n'
        '    jump expression "end_" + "game"\n',
        'label start:\n'
        '    jump ending\n'
        '    jump expression "end_" + "game"\n',
      );
    });

    test('menu with caption and conditional choice', () {
      const text =
          'label start:\n'
          '    menu:\n'
          '        "Which way?"\n'
          '        "Left" if brave:\n'
          '            jump left_path\n'
          '        "Right":\n'
          '            "You went right."\n';
      expectEmits(text, text);
    });

    test('if / elif / else', () {
      const text =
          'label start:\n'
          '    if points > 3:\n'
          '        e "Lots."\n'
          '    elif points > 1:\n'
          '        e "Some."\n'
          '    else:\n'
          '        e "None."\n';
      expectEmits(text, text);
    });

    test('show with all clauses', () {
      const text =
          'label start:\n'
          '    show eileen happy at left behind curtain onlayer master'
          ' zorder 2 with dissolve\n';
      expectEmits(text, text);
    });

    test('scene and hide', () {
      const text =
          'label start:\n'
          '    scene bg room at left onlayer master zorder 1 with fade\n'
          '    hide eileen onlayer master with dissolve\n';
      expectEmits(text, text);
    });

    test('play and stop with fadeout', () {
      const text =
          'label start:\n'
          '    play music "theme.ogg"\n'
          '    stop music fadeout 1.0\n';
      expectEmits(text, text);
    });

    test('define and default', () {
      const text =
          'define e = Character("Eileen")\n'
          'default points = 0\n';
      expectEmits(text, text);
    });

    test(r'$ one-liner stays $; $ assignment normalizes to define', () {
      expectEmits(
        'label start:\n'
        r'    $ renpy.pause(0.5)'
        '\n'
        r'    $ score = 10'
        '\n',
        'label start:\n'
        r'    $ renpy.pause(0.5)'
        '\n'
        '    define score = 10\n',
      );
    });

    test('python block', () {
      const text =
          'label start:\n'
          '    python:\n'
          '        x = 1\n'
          '        y = 2\n';
      expectEmits(text, text);
    });

    test('init python with priority', () {
      const text =
          'init -2 python:\n'
          '    foo = 1\n'
          '    def helper():\n'
          '        return foo\n';
      expectEmits(text, text);
    });

    test('image: ATL-body form vs assignment form', () {
      const text =
          'image eileen happy = "eileen_happy.png"\n'
          'image moving:\n'
          '    "eileen_happy.png"\n'
          '    xpos 0.0\n'
          '    linear 2.0 xpos 1.0\n';
      expectEmits(text, text);
    });

    test('while / for / break / continue / pass / return', () {
      const text =
          'label start:\n'
          '    while points < 10:\n'
          '        if points == 5:\n'
          '            continue\n'
          '        if points == 9:\n'
          '            break\n'
          '    for q in questions:\n'
          '        pass\n'
          '    return points\n';
      expectEmits(text, text);
    });

    test('empty block emits an explicit pass', () {
      final label = RenPyLabelStatement('empty', [], 'test.rpy', 1);
      expect(
        emitter.emitStatement(label),
        'label empty:\n'
        '    pass',
      );
    });

    test('emitStatement honors the depth argument', () {
      final jump = RenPyJumpStatement('ending', 'test.rpy', 1);
      expect(emitter.emitStatement(jump, 2), '        jump ending');
    });

    test('custom indent string is used for nesting', () {
      const twoSpace = RenPyEmitter(indent: '  ');
      final script = parser
          .parse(
            'label start:\n'
            '    if ok:\n'
            '        return\n',
            'test.rpy',
          )
          .script;
      expect(
        twoSpace.emitScript(script),
        'label start:\n'
        '  if ok:\n'
        '    return\n',
      );
    });
  });
}

const _comprehensiveSnippet = r'''
define e = Character("Eileen")
default points = 0
init offset = 2
init python:
    foo = 1
init 2:
    define bar = 3
image eileen happy = "eileen_happy.png"
image moving:
    "eileen_happy.png"
    xpos 0.0
    linear 2.0 xpos 1.0
layeredimage eileen:
    always:
        "eileen_base"
    group outfit:
        attribute dress default:
            "eileen_dress"
    if points > 5:
        "eileen_crown"
transform slide:
    xpos 0.0
    linear 1.0 xpos 0.5
    pause 0.5
    repeat 3
screen hello_screen(who):
    tag menu
    vbox:
        text "Hello [who]!"
        if points > 0:
            text "Points!"
        else:
            text "No points."
        for q in questions:
            textbutton q action Return(q)
style say_dialogue is default:
    xalign 0.5
label start(chapter=1):
    $ points += 1
    python:
        x = 1
    scene bg room with fade
    show eileen happy at left behind curtain onlayer master zorder 2 with dissolve
    e happy @ vhappy "Hello there!"
    voice "line01.ogg"
    play music "theme.ogg"
    queue sound "ding.ogg"
    stop music fadeout 1.0
    window show dissolve
    pause 0.5
    nvl clear
    camera bg at zoom
    menu choice_menu:
        "What now?"
        set seen_choices
        "Go left" if points > 0:
            jump left_path
        "Go right":
            call right_path(1, 2)
    if points > 3:
        e "Lots."
    elif points > 1:
        e "Some."
    else:
        e "None."
    while points < 10:
        $ points += 1
        if points == 5:
            continue
        if points == 9:
            break
    for q in questions:
        e "[q]"
    hide eileen onlayer master with dissolve
    with fade
    call expression "left" + "_path"
    call screen hello_screen("you")
    jump expression "end_" + "game"
    pass
    return points
label left_path:
    return
label right_path(a, b=2):
    return
''';
