import 'dart:convert';
import 'dart:io';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/src/fly_codec.dart';
import 'package:test/test.dart';

const codec = FlyCodec();

/// Structural JSON equality: maps compared by key set (order-insensitive),
/// lists element-wise in order, scalars by ==.
bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Parses [rpy], encodes it, runs the encoding through a JSON string cycle,
/// decodes it back to an AST, re-encodes that AST, and asserts the two
/// encodings are deeply equal. Returns the first encoding.
Map<String, Object?> roundTrip(String rpy) {
  final script = RenPyParser().parse(rpy, 'test.rpy').script;
  final encoded = codec.encodeScript(script);

  // String cycle: what we write to disk must decode identically.
  final text = codec.encodeToString(script);
  final fromText = jsonDecode(text) as Map<String, Object?>;
  expect(deepEquals(encoded, fromText), isTrue,
      reason: 'JSON string cycle changed the document');

  final decoded = codec.decodeScript(fromText);
  final reEncoded = codec.encodeScript(decoded);
  expect(deepEquals(encoded, reEncoded), isTrue,
      reason: 'decode/encode round-trip changed the document:\n'
          'first:  ${jsonEncode(encoded)}\n'
          'second: ${jsonEncode(reEncoded)}');
  return encoded;
}

/// Collects every "type" discriminator appearing anywhere in [node].
Set<String> collectTypes(Object? node) {
  final types = <String>{};
  void walk(Object? v) {
    if (v is Map) {
      final t = v['type'];
      if (t is String) types.add(t);
      v.values.forEach(walk);
    } else if (v is List) {
      v.forEach(walk);
    }
  }

  walk(node);
  return types;
}

List<Map<String, Object?>> scriptOf(Map<String, Object?> doc) =>
    (doc['script'] as List).cast<Map<String, Object?>>();

void main() {
  group('round-trip per statement family', () {
    test('label, say, jump, return', () {
      final doc = roundTrip('''
label start(chapter=1, *args):
    e happy @ vhappy "Hello there!"
    "Plain narration."
    jump ending
label ending:
    return 42
''');
      final label = scriptOf(doc)[0];
      expect(label['type'], 'label');
      expect(label['name'], 'start');
      expect(label['parameters'], [
        {'name': 'chapter', 'default_expression': '1'},
        {'name': '*args'},
      ]);
      final block = (label['block'] as List).cast<Map<String, Object?>>();
      expect(block[0]['type'], 'say');
      expect(block[0]['character'], 'e');
      expect(block[0]['attributes'], ['happy']);
      expect(block[0]['temporary_attributes'], ['vhappy']);
      expect(block[1].containsKey('character'), isFalse,
          reason: 'narrator say must omit the null character');
      expect(block[2], {'type': 'jump', 'target': 'ending'});
    });

    test('menu with caption, set, name, and conditions', () {
      final doc = roundTrip('''
label start:
    menu retry_menu:
        "Which way?"
        set seen_choices
        "Left" if brave:
            jump left
        "Right":
            "You went right."
''');
      final menu =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>()[0];
      expect(menu['type'], 'menu');
      expect(menu['name'], 'retry_menu');
      expect(menu['caption'], 'Which way?');
      expect(menu['set_variable'], 'seen_choices');
      final items = (menu['items'] as List).cast<Map<String, Object?>>();
      expect(items[0]['text'], 'Left');
      expect(items[0]['condition'], 'brave');
      expect(items[1]['text'], 'Right');
      expect(items[1]['condition'], 'True',
          reason: 'unconditioned choices store the literal "True"');
    });

    test('call forms: plain, args, expression, screen', () {
      final doc = roundTrip('''
label start:
    call subroutine
    call subroutine(1, 2)
    call expression "sub" + "routine"
    call screen confirm_screen("Quit?")
''');
      final block =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>();
      expect(block[0], {'type': 'call', 'target': 'subroutine'});
      expect(block[1]['call_args'], '1, 2');
      expect(block[2]['is_expression'], true);
      expect(block[3]['is_screen'], true);
      expect(block[3]['screen_name'], 'confirm_screen');
      expect(block[3]['screen_args'], '"Quit?"');
    });

    test('show, scene, hide, with', () {
      final doc = roundTrip('''
label start:
    scene bg room with fade
    show eileen happy at left behind curtain onlayer master zorder 2 with dissolve
    hide eileen onlayer master with dissolve
    with fade
''');
      final block =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>();
      expect(block[0]['type'], 'scene');
      expect(block[0]['with_expression'], 'fade');
      expect(block[1]['type'], 'show');
      expect(block[1]['at_expression'], 'left');
      expect(block[1]['behind_expression'], 'curtain');
      expect(block[1]['on_layer_expression'], 'master');
      expect(block[1]['z_order_expression'], '2');
      expect(block[2]['type'], 'hide');
      expect(block[3], {'type': 'with', 'transition': 'fade'});
    });

    test('image: assignment and ATL-body forms', () {
      final doc = roundTrip('''
image eileen happy = "eileen_happy.png"
image moving:
    "eileen_happy.png"
    xpos 0.0
    linear 2.0 xpos 1.0
''');
      final script = scriptOf(doc);
      expect(script[0]['expression'], '"eileen_happy.png"');
      expect(script[0].containsKey('body'), isFalse);
      expect(script[1].containsKey('expression'), isFalse,
          reason: 'ATL-form image has an empty expression, which is omitted');
      expect(script[1]['body'], isA<List<Object?>>());
    });

    test('layeredimage with always/attribute/condition layers', () {
      final doc = roundTrip('''
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
      final layers =
          (scriptOf(doc)[0]['layers'] as List).cast<Map<String, Object?>>();
      expect(layers[0]['kind'], 'always');
      expect(layers[1]['kind'], 'attribute');
      expect(layers[1]['group'], 'outfit');
      expect(layers[1]['is_default'], true);
      expect(layers[2].containsKey('is_default'), isFalse,
          reason: 'false booleans are omitted');
      expect(layers[3]['kind'], 'condition');
      expect(layers[3]['condition'], 'points > 5');
    });

    test('transform with structured ATL', () {
      final doc = roundTrip('''
transform slide:
    xpos 0.0
    linear 1.0 xpos 0.5
    pause 0.5
    repeat 3
''');
      final transform = scriptOf(doc)[0];
      expect(transform['signature'], 'slide');
      final atl = (transform['atl'] as List).cast<Map<String, Object?>>();
      expect(atl.map((n) => n['node_kind']),
          containsAll(['property', 'interpolation', 'pause', 'repeat']));
    });

    test('audio: play, queue, voice, stop', () {
      final doc = roundTrip('''
label start:
    play music "theme.ogg"
    queue sound "ding.ogg"
    voice "line01.ogg"
    voice sustain
    stop music fadeout 1.0
''');
      final block =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>();
      expect(block[0], {'type': 'play', 'channel': 'music', 'expression': '"theme.ogg"'});
      expect(block[1]['type'], 'queue');
      expect(block[2]['expression'], '"line01.ogg"');
      expect(block[3]['expression'], 'sustain');
      expect(block[4]['fadeout'], '1.0');
    });

    test('pause, window, nvl', () {
      final doc = roundTrip('''
label start:
    pause 0.5
    pause
    window show dissolve
    window hide
    window auto
    nvl clear
''');
      final block =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>();
      expect(block[0]['duration'], '0.5');
      expect(block[1], {'type': 'pause'});
      expect(block[2], {'type': 'window', 'action': 'show', 'transition': 'dissolve'});
      expect(block[3], {'type': 'window', 'action': 'hide'});
      expect(block[4], {'type': 'window', 'action': 'auto'});
      expect(block[5], {'type': 'nvl', 'action': 'clear'});
    });

    test('python, init, init offset, define, default', () {
      roundTrip('''
init offset = 2
init python:
    foo = 1
init 2:
    define bar = 3
define e = Character("Eileen")
default points = 0
label start:
    \$ points += 1
    python:
        x = 1
        y = 2
''');
    });

    test('screen with keywords, if-chain, for-loop', () {
      final doc = roundTrip('''
screen hello_screen(who):
    tag menu
    vbox:
        spacing 10
        text "Hello [who]!"
        if points > 0:
            text "You have points."
        else:
            text "No points."
        for q in questions:
            textbutton q action Return(q)
''');
      final screen = scriptOf(doc)[0];
      expect(screen['signature'], 'hello_screen(who)');
      final children =
          (screen['children'] as List).cast<Map<String, Object?>>();
      expect(children[0]['node_kind'], 'keyword');
      final vbox = children[1];
      expect(vbox['node_kind'], 'displayable');
      final vboxChildren =
          (vbox['children'] as List).cast<Map<String, Object?>>();
      final ifChain =
          vboxChildren.firstWhere((n) => n['node_kind'] == 'if_chain');
      final branches =
          (ifChain['branches'] as List).cast<Map<String, Object?>>();
      expect(branches.last['condition'], 'True',
          reason: 'screen else-branches store the literal "True"');
      expect(vboxChildren.any((n) => n['node_kind'] == 'for_loop'), isTrue);
    });

    test('style with structured properties', () {
      final doc = roundTrip('''
style say_dialogue is default:
    xalign 0.5
''');
      final style = scriptOf(doc)[0];
      expect(style['declaration'], 'say_dialogue is default');
      expect(style['style'], {
        'name': 'say_dialogue',
        'parent': 'default',
        'properties': {'xalign': '0.5'},
      });
    });

    test('if/elif/else, while, for, break, continue, pass', () {
      final doc = roundTrip('''
label start:
    if points > 3:
        e "Lots."
    elif points > 1:
        e "Some."
    else:
        e "None."
    while points < 10:
        \$ points += 1
        if points == 5:
            continue
        if points == 9:
            break
    for q in questions:
        e "[q]"
    pass
''');
      final block =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>();
      final branches =
          (block[0]['branches'] as List).cast<Map<String, Object?>>();
      expect(branches.map((b) => b['condition']),
          ['points > 3', 'points > 1', 'True'],
          reason: 'the parser stores else as the literal condition "True"');
      expect(block[1]['type'], 'while');
      expect(block[2], containsPair('variable', 'q'));
      expect(block[3], {'type': 'pass'});
    });

    test('raw (generic) statements survive', () {
      final doc = roundTrip('''
label start:
    camera bg at zoom
''');
      final block =
          (scriptOf(doc)[0]['block'] as List).cast<Map<String, Object?>>();
      expect(block[0], {'type': 'raw', 'text': 'camera bg at zoom'});
    });

    test('comprehensive snippet covers every statement type', () {
      final doc = roundTrip(_comprehensiveSnippet);
      expect(collectTypes(doc), {
        'label', 'say', 'menu', 'jump', 'call', 'show', 'scene', 'hide',
        'image', 'layeredimage', 'with', 'transform', 'play', 'queue',
        'voice', 'stop', 'pause', 'window', 'python', 'init', 'init_offset',
        'define', 'default', 'screen', 'style', 'nvl', 'if', 'while', 'for',
        'break', 'continue', 'pass', 'return', 'raw', // all 34
      });
    });
  });

  group('encodeToString', () {
    test('pretty output uses two-space indentation', () {
      final script = RenPyParser().parse('label start:\n    "Hi."\n', 'p.rpy').script;
      final pretty = codec.encodeToString(script);
      expect(pretty, contains('\n  "format": "fly",\n'));
      final compact = codec.encodeToString(script, pretty: false);
      expect(compact, isNot(contains('\n')));
      expect(jsonDecode(pretty), equals(jsonDecode(compact)));
    });

    test('decoding synthesizes filename and line numbers', () {
      final script =
          RenPyParser().parse('label start:\n    "Hi."\n', 'orig.rpy').script;
      final decoded = codec.decodeFromString(codec.encodeToString(script),
          filename: 'story.fly');
      final label = decoded.statements[0] as RenPyLabelStatement;
      expect(label.filename, 'story.fly');
      expect(label.linenumber, greaterThan(0));
      expect(label.block[0].filename, 'story.fly');
    });
  });

  group('real fixtures', () {
    const fixtures = [
      '../../apps/renfly_player/assets/games/the_question/game/script.rpy',
      '../../apps/renfly_player/assets/games/4/game/script.rpy',
    ];

    for (final path in fixtures) {
      test(path, () {
        final source = File(path).readAsStringSync();
        final script = RenPyParser().parse(source, path).script;
        final first = codec.encodeScript(script);
        final decoded =
            codec.decodeFromString(codec.encodeToString(script));
        final second = codec.encodeScript(decoded);
        expect(deepEquals(first, second), isTrue,
            reason: 'fixture $path did not round-trip losslessly');
        expect(scriptOf(first), isNotEmpty);
      });
    }
  });

  group('strictness', () {
    void expectThrowsAt(Map<String, Object?> document, String expectedPath,
        {String? messageContains}) {
      try {
        codec.decodeScript(document);
        fail('expected FlyFormatException for $document');
      } on FlyFormatException catch (e) {
        expect(e.path, expectedPath, reason: e.toString());
        if (messageContains != null) {
          expect(e.message, contains(messageContains));
        }
        expect(e.toString(), contains('FlyFormatException'));
      }
    }

    Map<String, Object?> doc(List<Object?> script) =>
        {'format': 'fly', 'version': 1, 'script': script};

    test('wrong format value', () {
      expectThrowsAt({'format': 'butterfly', 'version': 1, 'script': []},
          '/format', messageContains: 'fly');
    });

    test('missing format', () {
      expectThrowsAt({'version': 1, 'script': []}, '',
          messageContains: 'format');
    });

    test('missing version', () {
      expectThrowsAt({'format': 'fly', 'script': []}, '',
          messageContains: 'version');
    });

    test('non-integer version', () {
      expectThrowsAt({'format': 'fly', 'version': '1', 'script': []},
          '/version', messageContains: 'integer');
    });

    test('unsupported version', () {
      expectThrowsAt({'format': 'fly', 'version': 99, 'script': []},
          '/version', messageContains: 'unsupported');
    });

    test('unknown document key', () {
      expectThrowsAt(
          {'format': 'fly', 'version': 1, 'script': [], 'extra': true},
          '/extra',
          messageContains: 'unknown');
    });

    test('script is not a list', () {
      expectThrowsAt({'format': 'fly', 'version': 1, 'script': 'nope'},
          '/script', messageContains: 'list');
    });

    test('non-object statement', () {
      expectThrowsAt(doc(['jump start']), '/script/0',
          messageContains: 'object');
    });

    test('statement without type', () {
      expectThrowsAt(doc([{'target': 'start'}]), '/script/0',
          messageContains: 'type');
    });

    test('unknown statement type', () {
      expectThrowsAt(doc([{'type': 'teleport', 'target': 'start'}]),
          '/script/0/type', messageContains: 'unknown statement type');
    });

    test('unknown key within a statement', () {
      expectThrowsAt(
          doc([{'type': 'jump', 'target': 'start', 'speed': 'fast'}]),
          '/script/0/speed',
          messageContains: 'unknown key');
    });

    test('missing required field', () {
      expectThrowsAt(doc([{'type': 'jump'}]), '/script/0',
          messageContains: 'target');
    });

    test('wrong-typed field: block is not a list', () {
      expectThrowsAt(
          doc([{'type': 'label', 'name': 'start', 'block': 'notalist'}]),
          '/script/0/block',
          messageContains: 'list');
    });

    test('wrong-typed field: say text is not a string', () {
      expectThrowsAt(doc([{'type': 'say', 'text': 5}]), '/script/0/text',
          messageContains: 'string');
    });

    test('wrong-typed nested field reports a deep path', () {
      expectThrowsAt(
          doc([
            {
              'type': 'menu',
              'items': [
                {'text': 7, 'block': []},
              ],
            },
          ]),
          '/script/0/items/0/text');
    });

    test('bad enum values', () {
      expectThrowsAt(doc([{'type': 'window', 'action': 'maximize'}]),
          '/script/0/action');
      expectThrowsAt(doc([{'type': 'nvl', 'action': 'flush'}]),
          '/script/0/action');
      expectThrowsAt(
          doc([
            {
              'type': 'layeredimage',
              'name': 'x',
              'layers': [
                {'kind': 'sometimes', 'displayable': '"y"'},
              ],
            },
          ]),
          '/script/0/layers/0/kind');
    });

    test('malformed nested statement inside a block', () {
      expectThrowsAt(
          doc([
            {
              'type': 'label',
              'name': 'start',
              'block': [
                {'type': 'say', 'text': 'hi', 'volume': 11},
              ],
            },
          ]),
          '/script/0/block/0/volume');
    });

    test('invalid JSON text', () {
      expect(
        () => codec.decodeFromString('{not json'),
        throwsA(isA<FlyFormatException>()
            .having((e) => e.message, 'message', contains('JSON'))),
      );
    });

    test('non-object JSON document', () {
      expect(
        () => codec.decodeFromString('[1, 2, 3]'),
        throwsA(isA<FlyFormatException>()),
      );
    });
  });

  group('hand-written documents', () {
    test('a hand-authored .fly decodes to the expected AST', () {
      const source = '''
{
  "format": "fly",
  "version": 1,
  "script": [
    {"type": "define", "name": "e", "expression": "Character(\\"Eileen\\")"},
    {
      "type": "label",
      "name": "start",
      "block": [
        {"type": "scene", "image_name": "bg room"},
        {"type": "show", "image_name": "eileen happy"},
        {"type": "say", "character": "e", "text": "Welcome to .fly!"},
        {"type": "say", "text": "Narration needs no character."},
        {
          "type": "menu",
          "items": [
            {
              "text": "Sounds great.",
              "block": [{"type": "jump", "target": "good_end"}]
            },
            {
              "text": "I prefer .rpy.",
              "condition": "stubborn",
              "block": [{"type": "return"}]
            }
          ]
        }
      ]
    },
    {
      "type": "label",
      "name": "good_end",
      "block": [
        {"type": "say", "character": "e", "text": "Hooray!"},
        {"type": "return"}
      ]
    }
  ]
}
''';
      final script = codec.decodeFromString(source, filename: 'story.fly');
      expect(script.statements, hasLength(3));

      final define = script.statements[0] as RenPyDefineStatement;
      expect(define.name, 'e');

      final start = script.statements[1] as RenPyLabelStatement;
      expect(start.name, 'start');
      expect(start.parameters, isEmpty);
      expect(start.block, hasLength(5));
      expect(start.block[0], isA<RenPySceneStatement>());
      expect(start.block[1], isA<RenPyShowStatement>());

      final say = start.block[2] as RenPySayStatement;
      expect(say.character, 'e');
      expect(say.text, 'Welcome to .fly!');

      final narration = start.block[3] as RenPySayStatement;
      expect(narration.character, isNull);

      final menu = start.block[4] as RenPyMenuStatement;
      expect(menu.items, hasLength(2));
      expect(menu.items[0].condition, 'True',
          reason: 'omitted choice condition defaults to "True"');
      expect(menu.items[1].condition, 'stubborn');
      expect(menu.items[0].block.single, isA<RenPyJumpStatement>());

      expect(script.labels.keys, containsAll(['start', 'good_end']));

      // The hand-written document also re-encodes losslessly (modulo the
      // omitted-default normalization).
      final reEncoded = codec.encodeScript(script);
      final reDecoded = codec.decodeScript(reEncoded);
      expect(deepEquals(reEncoded, codec.encodeScript(reDecoded)), isTrue);
    });
  });
}

const _comprehensiveSnippet = '''
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
    \$ points += 1
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
        \$ points += 1
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
