import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/renpy_writer.dart';
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

/// A tiny but valid .fly document, produced by the real codec.
String smallStoryAsFly() {
  final parsed = RenPyParser().parse(smallStory, 'script.rpy').script;
  return const FlyCodec().encodeToString(parsed);
}

/// Matches a [FlyArchiveException] whose message contains [needle].
Matcher throwsFlyArchiveException(Object needle) {
  return throwsA(
    isA<FlyArchiveException>().having(
      (e) => e.message,
      'message',
      contains(needle),
    ),
  );
}

void main() {
  group('FlyStreamManifest encode/decode', () {
    test('round-trips with a name', () {
      final manifest = FlyStreamManifest(
        name: 'My Game',
        script: 'game/script.fly',
        files: ['game/images/bg meadow.png', 'game/script.fly'],
      );

      final json = manifest.encode();
      final decoded = FlyStreamManifest.decode(json);

      expect(decoded.name, 'My Game');
      expect(decoded.script, 'game/script.fly');
      expect(decoded.files, ['game/images/bg meadow.png', 'game/script.fly']);
      expect(decoded.sizes, isNull);
      expect(jsonDecode(json), {
        'version': 1,
        'name': 'My Game',
        'script': 'game/script.fly',
        'files': ['game/images/bg meadow.png', 'game/script.fly'],
      });
    });

    test('round-trips with sizes', () {
      final manifest = FlyStreamManifest(
        name: 'My Game',
        script: 'game/script.fly',
        files: ['game/images/bg meadow.png', 'game/script.fly'],
        sizes: {
          // Deliberately unsorted: the manifest stores sizes sorted by path.
          'game/script.fly': 512,
          'game/images/bg meadow.png': 2048,
        },
      );

      final json = manifest.encode();
      final decoded = FlyStreamManifest.decode(json);

      expect(decoded.sizes, {
        'game/images/bg meadow.png': 2048,
        'game/script.fly': 512,
      });
      expect(jsonDecode(json), {
        'version': 1,
        'name': 'My Game',
        'script': 'game/script.fly',
        'files': ['game/images/bg meadow.png', 'game/script.fly'],
        'sizes': {'game/images/bg meadow.png': 2048, 'game/script.fly': 512},
      });
    });

    test('allows partial sizes (any subset of files)', () {
      final manifest = FlyStreamManifest(
        script: 'game/script.fly',
        files: ['game/images/bg.png', 'game/script.fly'],
        sizes: {'game/script.fly': 512},
      );

      final decoded = FlyStreamManifest.decode(manifest.encode());
      expect(decoded.sizes, {'game/script.fly': 512});
    });

    test('rejects sizes paths that are not listed in files', () {
      expect(
        () => FlyStreamManifest(
          script: 'game/script.fly',
          files: ['game/script.fly'],
          sizes: {'game/images/bg.png': 2048},
        ),
        throwsFlyArchiveException(
          'sizes path "game/images/bg.png" is not listed',
        ),
      );
    });

    test('rejects negative sizes', () {
      expect(
        () => FlyStreamManifest(
          script: 'game/script.fly',
          files: ['game/script.fly'],
          sizes: {'game/script.fly': -1},
        ),
        throwsFlyArchiveException('negative byte length'),
      );
    });

    test('sizes is unmodifiable', () {
      final manifest = FlyStreamManifest(
        script: 'game/script.fly',
        files: ['game/script.fly'],
        sizes: {'game/script.fly': 512},
      );
      expect(
        () => manifest.sizes!['game/script.fly'] = 0,
        throwsUnsupportedError,
      );
    });

    test('decode accepts a missing sizes key as null', () {
      final decoded = FlyStreamManifest.decode(
        '{"version": 1, "script": "game/script.fly", '
        '"files": ["game/script.fly"]}',
      );
      expect(decoded.sizes, isNull);
    });

    test('decode rejects a sizes value that is not an object', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly"], "sizes": [512]}',
        ),
        throwsFlyArchiveException('"sizes" must be an object'),
      );
    });

    test('decode rejects non-integer sizes values', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly"], '
          '"sizes": {"game/script.fly": "big"}}',
        ),
        throwsFlyArchiveException('only integer byte lengths'),
      );
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly"], '
          '"sizes": {"game/script.fly": 1.5}}',
        ),
        throwsFlyArchiveException('only integer byte lengths'),
      );
    });

    test('decode rejects sizes paths that are not listed in files', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly"], '
          '"sizes": {"game/images/bg.png": 2048}}',
        ),
        throwsFlyArchiveException(
          'sizes path "game/images/bg.png" is not listed',
        ),
      );
    });

    test('omits a null name and round-trips', () {
      final manifest = FlyStreamManifest(
        script: 'game/script.fly',
        files: ['game/script.fly'],
      );

      final json = manifest.encode();
      expect(jsonDecode(json), isNot(contains('name')));

      final decoded = FlyStreamManifest.decode(json);
      expect(decoded.name, isNull);
      expect(decoded.script, 'game/script.fly');
    });

    test('decode accepts a missing version', () {
      final decoded = FlyStreamManifest.decode(
        '{"script": "game/script.fly", "files": ["game/script.fly"]}',
      );
      expect(decoded.script, 'game/script.fly');
    });

    test('decode rejects an unsupported version', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 2, "script": "game/script.fly", '
          '"files": ["game/script.fly"]}',
        ),
        throwsFlyArchiveException('unsupported'),
      );
    });

    test('decode rejects a missing script', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "files": ["game/script.fly"]}',
        ),
        throwsFlyArchiveException('missing the "script" key'),
      );
    });

    test('decode rejects a .rpy script with the migrate-first message', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.rpy", '
          '"files": ["game/script.rpy"]}',
        ),
        throwsFlyArchiveException(
          '.rpy games must be migrated to .fly before streaming',
        ),
      );
    });

    test('decode rejects a script that is not listed in files', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/images/bg.png"]}',
        ),
        throwsFlyArchiveException('not listed'),
      );
    });

    test('decode rejects unsafe paths (zip-slip rules)', () {
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly", "../evil"]}',
        ),
        throwsFlyArchiveException('".." segment'),
      );
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly", "/etc/passwd"]}',
        ),
        throwsFlyArchiveException('absolute'),
      );
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "/game/script.fly", '
          '"files": ["/game/script.fly"]}',
        ),
        throwsFlyArchiveException('absolute'),
      );
    });

    test('decode rejects non-object documents and wrong field types', () {
      expect(
        () => FlyStreamManifest.decode('not json at all'),
        throwsFlyArchiveException('not valid JSON'),
      );
      expect(
        () => FlyStreamManifest.decode('[1, 2, 3]'),
        throwsFlyArchiveException('must be a JSON object'),
      );
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", "files": "nope"}',
        ),
        throwsFlyArchiveException('"files" must be a list'),
      );
      expect(
        () => FlyStreamManifest.decode(
          '{"version": 1, "script": "game/script.fly", '
          '"files": ["game/script.fly", 7]}',
        ),
        throwsFlyArchiveException('only string paths'),
      );
    });
  });

  group('FlyStreamManifest.fromFiles', () {
    test('selects the script and keeps every file, sorted', () {
      final manifest = FlyStreamManifest.fromFiles([
        'game/script.fly',
        'game/images/bg.png',
        'game/audio/theme.ogg',
      ], name: 'Demo');
      expect(manifest.name, 'Demo');
      expect(manifest.script, 'game/script.fly');
      expect(manifest.files, [
        'game/audio/theme.ogg',
        'game/images/bg.png',
        'game/script.fly',
      ]);
      expect(manifest.sizes, isNull);
    });

    test('passes sizes through to the manifest', () {
      final manifest = FlyStreamManifest.fromFiles(
        ['game/script.fly', 'game/images/bg.png'],
        sizes: {'game/script.fly': 512, 'game/images/bg.png': 2048},
      );
      expect(manifest.sizes, {
        'game/images/bg.png': 2048,
        'game/script.fly': 512,
      });
    });

    test('rejects sizes paths that are not in the file list', () {
      expect(
        () => FlyStreamManifest.fromFiles(
          ['game/script.fly'],
          sizes: {'game/images/bg.png': 2048},
        ),
        throwsFlyArchiveException(
          'sizes path "game/images/bg.png" is not listed',
        ),
      );
    });

    test('.fly beats .rpy', () {
      final manifest = FlyStreamManifest.fromFiles([
        'game/script.rpy',
        'game/script.fly',
      ]);
      expect(manifest.script, 'game/script.fly');
    });

    test('prefers game/script.fly among multiple .fly candidates', () {
      final manifest = FlyStreamManifest.fromFiles([
        'game/chapter2.fly',
        'game/script.fly',
      ]);
      expect(manifest.script, 'game/script.fly');
    });

    test('rejects a .rpy-only game with the migrate-first message', () {
      expect(
        () => FlyStreamManifest.fromFiles([
          'game/script.rpy',
          'game/images/bg.png',
        ]),
        throwsFlyArchiveException(
          '.rpy games must be migrated to .fly before streaming',
        ),
      );
    });

    test('rejects a game with no script at all', () {
      expect(
        () => FlyStreamManifest.fromFiles(['game/images/bg.png']),
        throwsFlyArchiveException('no script found'),
      );
    });

    test('rejects unsafe paths', () {
      expect(
        () => FlyStreamManifest.fromFiles(['game/script.fly', '../evil']),
        throwsFlyArchiveException('".." segment'),
      );
    });
  });

  group('buildStreamableDirectory', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('fly_stream_test');
    });

    tearDown(() {
      temp.deleteSync(recursive: true);
    });

    test('unpacks a .fly.zip into a tree plus manifest', () async {
      final image = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
      final zipBytes = FlyArchive.encode([
        FlyArchiveFile('game/script.fly', utf8.encode(smallStoryAsFly())),
        FlyArchiveFile('game/images/bg meadow.png', image),
      ]);
      final zipPath = '${temp.path}/demo.fly.zip';
      File(zipPath).writeAsBytesSync(zipBytes);
      final out = '${temp.path}/out';

      final result = await buildStreamableDirectory(
        input: zipPath,
        outputDir: out,
      );

      expect(result.scriptPath, 'game/script.fly');
      expect(result.migrationReport, isNull);
      expect(result.fileCount, 2);
      expect(
        result.totalBytes,
        utf8.encode(smallStoryAsFly()).length + image.length,
      );
      expect(File('$out/game/script.fly').existsSync(), isTrue);
      expect(File('$out/game/images/bg meadow.png').readAsBytesSync(), image);

      final manifest = FlyStreamManifest.decode(
        File('$out/${FlyStreamManifest.fileName}').readAsStringSync(),
      );
      expect(manifest.name, 'demo'); // .fly.zip suffix stripped
      expect(manifest.script, 'game/script.fly');
      expect(manifest.files, ['game/images/bg meadow.png', 'game/script.fly']);
      expect(manifest.sizes, {
        'game/images/bg meadow.png': image.length,
        'game/script.fly': utf8.encode(smallStoryAsFly()).length,
      });
    });

    test('migrates an .rpy directory input to .fly with a report', () async {
      final inDir = '${temp.path}/mygame';
      File('$inDir/game/script.rpy')
        ..createSync(recursive: true)
        ..writeAsStringSync(smallStory);
      File('$inDir/game/images/bg.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final out = '${temp.path}/out';

      final result = await buildStreamableDirectory(
        input: inDir,
        outputDir: out,
        name: 'My Game',
      );

      expect(result.migratedFrom, 'game/script.rpy');
      expect(result.migrationReport, isNotNull);
      expect(result.migrationReport!.isFaithful, isTrue);
      expect(result.scriptPath, 'game/script.fly');
      expect(File('$out/game/script.fly').existsSync(), isTrue);
      // The .rpy source is not copied: only .fly may stream.
      expect(File('$out/game/script.rpy').existsSync(), isFalse);

      final flyText = File('$out/game/script.fly').readAsStringSync();
      expect(jsonDecode(flyText), containsPair('format', 'fly'));

      final manifest = FlyStreamManifest.decode(
        File('$out/${FlyStreamManifest.fileName}').readAsStringSync(),
      );
      expect(manifest.name, 'My Game');
      expect(manifest.script, 'game/script.fly');
      expect(manifest.files, ['game/images/bg.png', 'game/script.fly']);
      // The migrated .fly script's size is recorded, not the .rpy source's.
      expect(manifest.sizes, {
        'game/images/bg.png': 3,
        'game/script.fly': File('$out/game/script.fly').lengthSync(),
      });
    });

    test(
      'treats a bare game directory (no game/ subtree) as the game root',
      () async {
        final inDir = '${temp.path}/bare';
        File('$inDir/script.fly')
          ..createSync(recursive: true)
          ..writeAsStringSync(smallStoryAsFly());
        final out = '${temp.path}/out';

        final result = await buildStreamableDirectory(
          input: inDir,
          outputDir: out,
        );

        expect(result.scriptPath, 'game/script.fly');
        expect(File('$out/game/script.fly').existsSync(), isTrue);
      },
    );

    test('regenerates a stale input manifest instead of copying it', () async {
      final inDir = '${temp.path}/stale';
      File('$inDir/game/script.fly')
        ..createSync(recursive: true)
        ..writeAsStringSync(smallStoryAsFly());
      File(
        '$inDir/${FlyStreamManifest.fileName}',
      ).writeAsStringSync('{"stale": true}');
      final out = '${temp.path}/out';

      final result = await buildStreamableDirectory(
        input: inDir,
        outputDir: out,
      );

      expect(result.manifest.files, ['game/script.fly']);
      final manifest = FlyStreamManifest.decode(
        File('$out/${FlyStreamManifest.fileName}').readAsStringSync(),
      );
      expect(manifest.script, 'game/script.fly');
    });

    test('refuses a non-empty output dir unless force', () async {
      final inDir = '${temp.path}/game_in';
      File('$inDir/game/script.fly')
        ..createSync(recursive: true)
        ..writeAsStringSync(smallStoryAsFly());
      final out = '${temp.path}/occupied';
      File('$out/leftover.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('old');

      await expectLater(
        buildStreamableDirectory(input: inDir, outputDir: out),
        throwsFlyArchiveException('not empty'),
      );

      final result = await buildStreamableDirectory(
        input: inDir,
        outputDir: out,
        force: true,
      );
      expect(result.scriptPath, 'game/script.fly');
      expect(File('$out/leftover.txt').existsSync(), isFalse);
      expect(File('$out/game/script.fly').existsSync(), isTrue);
    });

    test('fails clearly when an .rpy script does not parse', () async {
      // Inconsistent indentation is a hard parse error.
      const badIndent = 'label a:\n        "x"\n      "y"\n';
      final inDir = '${temp.path}/broken';
      File('$inDir/game/script.rpy')
        ..createSync(recursive: true)
        ..writeAsStringSync(badIndent);

      await expectLater(
        buildStreamableDirectory(input: inDir, outputDir: '${temp.path}/out'),
        throwsFlyArchiveException('does not parse'),
      );
    });

    test('rejects a missing input', () async {
      await expectLater(
        buildStreamableDirectory(
          input: '${temp.path}/nope',
          outputDir: '${temp.path}/out',
        ),
        throwsFlyArchiveException('does not exist'),
      );
    });
  });
}
