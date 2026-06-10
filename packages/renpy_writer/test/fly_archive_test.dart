import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/src/fly_archive.dart';
import 'package:renpy_writer/src/fly_codec.dart';
import 'package:test/test.dart';

const String smallStory = '''
define e = Character("Eileen")

label start:
    scene bg meadow
    e "Shall we explore?"
    jump explore

label explore:
    e "Off we go!"
    return
''';

/// The_question demo game script, relative to this package's root (the
/// working directory `dart test` runs in).
const String theQuestionPath =
    '../../apps/renfly_player/assets/games/the_question/game/script.rpy';

/// A tiny but valid .fly document, produced by the real codec.
String smallStoryAsFly() {
  final parsed = RenPyParser().parse(smallStory, 'script.rpy').script;
  return const FlyCodec().encodeToString(parsed);
}

void main() {
  group('encode/decode round-trip', () {
    test('keeps a .rpy script and assets byte-for-byte', () {
      final image = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 1, 2, 3]);
      final audio = Uint8List.fromList(List<int>.generate(256, (i) => i));
      final zip = FlyArchive.encode([
        FlyArchiveFile('game/script.rpy', utf8.encode(smallStory)),
        FlyArchiveFile('game/images/bg meadow.png', image),
        FlyArchiveFile('game/audio/theme.ogg', audio),
      ]);

      final archive = FlyArchive.decode(zip);

      expect(archive.scriptPath, 'game/script.rpy');
      expect(archive.scriptIsFly, isFalse);
      expect(archive.scriptSource, smallStory);
      expect(archive.scriptAsRpy(), smallStory);
      expect(archive.notes, isEmpty);

      final byPath = {for (final f in archive.files) f.path: f.bytes};
      expect(
        byPath.keys,
        unorderedEquals([
          'game/script.rpy',
          'game/images/bg meadow.png',
          'game/audio/theme.ogg',
        ]),
      );
      expect(byPath['game/script.rpy'], utf8.encode(smallStory));
      expect(byPath['game/images/bg meadow.png'], image);
      expect(byPath['game/audio/theme.ogg'], audio);
    });
  });

  group('fromScript', () {
    test('storeAsFly: true stores a .fly script that converts back', () {
      final zip = FlyArchive.fromScript(
        scriptSource: smallStory,
        storeAsFly: true,
        assets: [
          FlyArchiveFile('images/bg meadow.png', Uint8List.fromList([1, 2])),
          // Already-prefixed paths are kept as-is.
          FlyArchiveFile('game/audio/theme.ogg', Uint8List.fromList([3, 4])),
        ],
      );

      final archive = FlyArchive.decode(zip);

      expect(archive.scriptPath, 'game/script.fly');
      expect(archive.scriptIsFly, isTrue);
      expect(jsonDecode(archive.scriptSource), containsPair('format', 'fly'));
      expect(
        [for (final f in archive.files) f.path],
        unorderedEquals([
          'game/script.fly',
          'game/images/bg meadow.png',
          'game/audio/theme.ogg',
        ]),
      );

      final rpy = archive.scriptAsRpy();
      final reparsed = RenPyParser().parse(rpy, 'script.rpy').script;
      expect(
        reparsed.statements,
        contains(
          isA<RenPyLabelStatement>().having((s) => s.name, 'name', 'start'),
        ),
      );
    });

    test('rejects script text that does not parse', () {
      // The parser is lenient about most malformed lines (it records
      // warnings); inconsistent indentation is a hard parse error.
      const badIndent = 'label a:\n        "x"\n      "y"\n';
      expect(
        () => FlyArchive.fromScript(scriptSource: badIndent),
        throwsA(isA<FlyArchiveException>()),
      );
    });
  });

  group('script selection', () {
    test('.fly wins over .rpy with a note', () {
      final zip = FlyArchive.encode([
        FlyArchiveFile('game/script.fly', utf8.encode(smallStoryAsFly())),
        FlyArchiveFile('game/script.rpy', utf8.encode(smallStory)),
      ]);

      final archive = FlyArchive.decode(zip);

      expect(archive.scriptPath, 'game/script.fly');
      expect(archive.scriptIsFly, isTrue);
      expect(
        archive.notes,
        contains('ignored game/script.rpy because game/script.fly is present'),
      );
      // The ignored .rpy is still preserved as a plain file entry.
      expect(
        [for (final f in archive.files) f.path],
        contains('game/script.rpy'),
      );
    });

    test('multiple scripts of the winning kind prefer game/script.<ext>', () {
      final zip = FlyArchive.encode([
        FlyArchiveFile('game/script.rpy', utf8.encode(smallStory)),
        FlyArchiveFile('game/chapter2.rpy', utf8.encode(smallStory)),
      ]);
      final archive = FlyArchive.decode(zip);
      expect(archive.scriptPath, 'game/script.rpy');
      expect(
        archive.notes,
        contains(
          'ignored game/chapter2.rpy because game/script.rpy is preferred',
        ),
      );
    });

    test('entries outside game/ are preserved but never the script', () {
      final zip = FlyArchive.encode([
        FlyArchiveFile('game/script.rpy', utf8.encode(smallStory)),
        FlyArchiveFile('README.md', utf8.encode('# hi')),
        FlyArchiveFile('extras/notes.rpy', utf8.encode('label x:\n    pass')),
      ]);
      final archive = FlyArchive.decode(zip);
      expect(archive.scriptPath, 'game/script.rpy');
      expect(archive.files, hasLength(3));
    });
  });

  group('errors', () {
    test('no script at all', () {
      expect(
        () => FlyArchive.encode([
          FlyArchiveFile('game/images/bg.png', Uint8List.fromList([1])),
        ]),
        throwsA(
          isA<FlyArchiveException>().having(
            (e) => e.message,
            'message',
            contains('no script found'),
          ),
        ),
      );
    });

    test('two .rpy scripts, neither named script.rpy', () {
      expect(
        () => FlyArchive.encode([
          FlyArchiveFile('game/intro.rpy', utf8.encode(smallStory)),
          FlyArchiveFile('game/outro.rpy', utf8.encode(smallStory)),
        ]),
        throwsA(
          isA<FlyArchiveException>().having(
            (e) => e.message,
            'message',
            contains('multiple .rpy scripts'),
          ),
        ),
      );
    });

    test('zip-slip entries are rejected on encode', () {
      expect(
        () => FlyArchive.encode([
          FlyArchiveFile('game/script.rpy', utf8.encode(smallStory)),
          FlyArchiveFile('../evil', Uint8List.fromList([1])),
        ]),
        throwsA(isA<FlyArchiveException>()),
      );
      expect(
        () => FlyArchive.encode([
          FlyArchiveFile('game/script.rpy', utf8.encode(smallStory)),
          FlyArchiveFile('/etc/passwd', Uint8List.fromList([1])),
        ]),
        throwsA(isA<FlyArchiveException>()),
      );
    });

    test('zip-slip entries are rejected on decode', () {
      // Build a hostile zip with the raw archive package, bypassing
      // FlyArchive.encode's own validation.
      final hostile = Archive()
        ..add(ArchiveFile.string('game/script.rpy', smallStory))
        ..add(ArchiveFile.string('../evil', 'muahaha'));
      final zipBytes = ZipEncoder().encodeBytes(hostile);

      expect(
        () => FlyArchive.decode(zipBytes),
        throwsA(
          isA<FlyArchiveException>().having(
            (e) => e.message,
            'message',
            contains('..'),
          ),
        ),
      );
    });

    test('garbage bytes are not a zip', () {
      expect(
        () => FlyArchive.decode(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FlyArchiveException>()),
      );
    });
  });

  group('real game', () {
    test('the_question survives fromScript -> decode -> scriptAsRpy', () {
      final source = File(theQuestionPath).readAsStringSync();
      final direct = RenPyParser().parse(source, 'script.rpy').script;

      final zip = FlyArchive.fromScript(scriptSource: source);
      final archive = FlyArchive.decode(zip);
      expect(archive.scriptIsFly, isTrue);

      final roundTripped =
          RenPyParser().parse(archive.scriptAsRpy(), 'script.rpy').script;
      expect(
        roundTripped.statements.length,
        direct.statements.length,
      );
    });
  });
}
