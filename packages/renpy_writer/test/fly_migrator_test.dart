import 'dart:io';

import 'package:renpy_writer/renpy_writer.dart';
import 'package:test/test.dart';

/// The renfly_editor starter template (apps/renfly_editor/lib/src/
/// starter_template.dart), copied here as the canonical "fresh project"
/// faithfulness fixture.
const String starterTemplate = '''
define e = Character("Eileen")

label start:
    scene black with dissolve
    "Welcome to RenFly Editor."
    show red at center
    e "Edit the script on the left, then press Run."
    menu:
        "Try a choice":
            e "Choices work too."
        "Skip":
            pass
    scene white
    e "That's the whole tour. Make something wonderful."
    return
''';

void main() {
  const migrator = FlyMigrator();

  group('reference games round-trip faithfully', () {
    const gameScripts = <String, String>{
      'the_question':
          '../../apps/renfly_player/assets/games/the_question/game/script.rpy',
      'game 3': '../../apps/renfly_player/assets/games/3/game/script.rpy',
      'game 4': '../../apps/renfly_player/assets/games/4/game/script.rpy',
    };

    for (final entry in gameScripts.entries) {
      test(entry.key, () {
        final source = File(entry.value).readAsStringSync();
        final report = migrator.verifyRoundTrip(source, filename: 'script.rpy');

        final divergences =
            report.issues
                .where((issue) => issue.kind == 'roundtrip-divergence')
                .toList();
        expect(
          divergences,
          isEmpty,
          reason:
              'round trip must not change the document:\n'
              '${divergences.join('\n')}',
        );

        // All three reference games are known to be fully structured: no
        // parser warnings, no unstructured statements, and no raw
        // passthrough bodies. Pin that so regressions surface.
        expect(
          report.issues,
          isEmpty,
          reason:
              'expected a fully faithful migration, got:\n'
              '${report.issues.join('\n')}',
        );
        expect(report.isFaithful, isTrue);
      });
    }
  });

  group('rpyToFly', () {
    test(
      'unrecognized construct surfaces as a lossy unstructured-statement',
      () {
        const source = '''
label start:
    camera bg with ease
    "hello"
''';
        final result = migrator.rpyToFly(source, filename: 'exotic.rpy');

        final unstructured =
            result.report.issues
                .where((issue) => issue.kind == 'unstructured-statement')
                .toList();
        expect(unstructured, hasLength(1));
        final issue = unstructured.single;
        expect(issue.severity, FlyMigrationSeverity.lossy);
        expect(issue.filename, 'exotic.rpy');
        expect(issue.linenumber, 2);
        expect(issue.snippet, 'camera bg with ease');
        expect(issue.message, contains('camera bg with ease'));
        expect(result.report.isFaithful, isFalse);

        // The raw text still travels through the .fly document.
        expect(result.output, contains('camera bg with ease'));
      },
    );

    test('parser warnings surface as parse-warning issues', () {
      const source = '''
menu:
    not_a_quoted_choice:
        pass
''';
      final result = migrator.rpyToFly(source, filename: 'warned.rpy');

      final warnings =
          result.report.issues
              .where((issue) => issue.kind == 'parse-warning')
              .toList();
      expect(warnings, isNotEmpty);
      final issue = warnings.first;
      expect(issue.severity, FlyMigrationSeverity.warning);
      expect(issue.message, contains('Invalid menu choice syntax'));
      expect(issue.filename, 'warned.rpy');
      expect(issue.linenumber, 2);
      expect(result.report.isFaithful, isFalse);
    });

    test('raw passthrough bodies are reported as info and stay faithful', () {
      const source = '''
image eyes blink:
    "eyes_open.png"
    pause 4.5
    repeat
''';
      final result = migrator.rpyToFly(source);

      final raw =
          result.report.issues
              .where((issue) => issue.kind == 'raw-passthrough-body')
              .toList();
      expect(raw, hasLength(1));
      expect(raw.single.severity, FlyMigrationSeverity.info);
      expect(raw.single.message, contains('eyes blink'));
      expect(raw.single.snippet, contains('pause 4.5'));

      // Info issues do not break faithfulness.
      expect(result.report.isFaithful, isTrue);
    });

    test('a clean script migrates with an empty report', () {
      final result = migrator.rpyToFly(starterTemplate);
      expect(result.report.issues, isEmpty);
      expect(result.report.isFaithful, isTrue);
      expect(result.output, contains('"format": "fly"'));
    });
  });

  group('flyToRpy', () {
    test('hand-authored document emits valid .rpy with a faithful report', () {
      const flySource = '''
{
  "format": "fly",
  "version": 1,
  "script": [
    {"type": "define", "name": "e", "expression": "Character(\\"Eileen\\")"},
    {
      "type": "label",
      "name": "start",
      "block": [
        {"type": "scene", "image_name": "black"},
        {"type": "say", "character": "e", "text": "Hello from .fly!"},
        {
          "type": "menu",
          "items": [
            {
              "text": "Continue",
              "block": [{"type": "jump", "target": "ending"}]
            },
            {"text": "Stop", "block": [{"type": "return"}]}
          ]
        }
      ]
    },
    {
      "type": "label",
      "name": "ending",
      "block": [
        {"type": "say", "text": "The end."},
        {"type": "return"}
      ]
    }
  ]
}
''';
      final result = migrator.flyToRpy(flySource);

      expect(result.report.issues, isEmpty);
      expect(result.report.isFaithful, isTrue);
      expect(result.output, contains('label start:'));
      expect(result.output, contains('e "Hello from .fly!"'));
      expect(result.output, contains('jump ending'));

      // The emitted text must itself round-trip.
      final verification = migrator.verifyRoundTrip(result.output);
      expect(verification.isFaithful, isTrue);
    });

    test('an invalid document is a hard error, not an issue', () {
      expect(
        () => migrator.flyToRpy('{"format": "not-fly"}'),
        throwsA(isA<FlyFormatException>()),
      );
      expect(
        () => migrator.flyToRpy('not json at all'),
        throwsA(isA<FlyFormatException>()),
      );
    });

    test('raw statements in the document are reported as unstructured', () {
      const flySource = '''
{
  "format": "fly",
  "version": 1,
  "script": [
    {
      "type": "label",
      "name": "start",
      "block": [
        {"type": "raw", "text": "camera bg with ease"},
        {"type": "return"}
      ]
    }
  ]
}
''';
      final result = migrator.flyToRpy(flySource);

      final unstructured =
          result.report.issues
              .where((issue) => issue.kind == 'unstructured-statement')
              .toList();
      expect(unstructured, hasLength(1));
      expect(unstructured.single.snippet, 'camera bg with ease');
      // The raw text re-parses to the same raw statement, so the round trip
      // itself does not diverge.
      expect(
        result.report.issues.where(
          (issue) => issue.kind == 'roundtrip-divergence',
        ),
        isEmpty,
      );
    });
  });

  group('verifyRoundTrip', () {
    test('editor starter template is fully faithful', () {
      final report = migrator.verifyRoundTrip(starterTemplate);
      expect(
        report.issues,
        isEmpty,
        reason:
            'expected a fully faithful round trip, got:\n'
            '${report.issues.join('\n')}',
      );
      expect(report.isFaithful, isTrue);
    });

    test('report summarizes severities', () {
      const source = '''
label start:
    camera bg with ease
''';
      final report = migrator.verifyRoundTrip(source);
      expect(report.isFaithful, isFalse);
      expect(report.lossyCount, greaterThan(0));
      expect(report.warningCount, greaterThan(0));
      expect(report.toString(), contains('NOT faithful'));
      final issue = report.issues.firstWhere(
        (i) => i.kind == 'unstructured-statement',
      );
      expect(issue.toString(), contains('unstructured-statement'));
      expect(issue.toString(), contains('script.rpy:2'));
    });
  });

  group('flyJsonDiff', () {
    test('reports JSON-pointer paths for scalar changes', () {
      final a = {
        'script': [
          {'type': 'say', 'text': 'Hello'},
          {'type': 'jump', 'target': 'start'},
        ],
      };
      final b = {
        'script': [
          {'type': 'say', 'text': 'Goodbye'},
          {'type': 'jump', 'target': 'ending'},
        ],
      };
      final paths = flyJsonDiff(a, b);
      expect(paths, hasLength(2));
      expect(paths[0], '/script/0/text: "Hello" != "Goodbye"');
      expect(paths[1], '/script/1/target: "start" != "ending"');
    });

    test('reports missing keys and list-length changes', () {
      final a = {
        'script': [
          {'type': 'say', 'text': 'Hello', 'character': 'e'},
          {'type': 'return'},
        ],
      };
      final b = {
        'script': [
          {'type': 'say', 'text': 'Hello'},
        ],
      };
      final paths = flyJsonDiff(a, b);
      expect(
        paths,
        containsAll(<String>[
          '/script/0/character: "e" != (absent)',
          '/script: list length 2 != 1',
        ]),
      );
    });

    test('escapes JSON-pointer special characters in keys', () {
      final paths = flyJsonDiff({'a/b~c': 1}, {'a/b~c': 2});
      expect(paths, ['/a~1b~0c: 1 != 2']);
    });

    test('caps the number of reported paths', () {
      final a = {for (var i = 0; i < 50; i++) 'k$i': 1};
      final b = {for (var i = 0; i < 50; i++) 'k$i': 2};
      expect(flyJsonDiff(a, b, maxPaths: 5), hasLength(5));
    });

    test('identical documents produce no paths', () {
      final doc = {
        'format': 'fly',
        'version': 1,
        'script': [
          {'type': 'return'},
        ],
      };
      expect(flyJsonDiff(doc, doc), isEmpty);
    });

    test('two slightly different encodes diverge at sane paths', () {
      const migratorA = FlyMigrator();
      final a = migratorA.rpyToFly('label start:\n    "Hello"\n');
      final b = migratorA.rpyToFly('label start:\n    "Goodbye"\n');
      const codec = FlyCodec();
      final docA = codec.decodeFromString(a.output);
      final docB = codec.decodeFromString(b.output);
      final paths = flyJsonDiff(
        codec.encodeScript(docA),
        codec.encodeScript(docB),
      );
      expect(paths, ['/script/0/block/0/text: "Hello" != "Goodbye"']);
    });
  });
}
