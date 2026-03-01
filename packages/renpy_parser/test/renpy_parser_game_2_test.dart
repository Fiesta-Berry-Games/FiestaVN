import 'dart:io';
import 'package:test/test.dart';
import 'package:renpy_parser/renpy_parser.dart';

void main() {
  group('002.rpy (menus, audio, transitions, python)', () {
    late RenPyParseResult result;

    setUpAll(() async {
      final file = File('test/games/2/game/script.rpy');
      final src  = await file.readAsString();
      result     = RenPyParser().parse(src, file.path);
    });

    test('parses without fatal errors', () {
      expect(result.script.statements, isNotEmpty);
    });

    test('top-level contains one menu with two choices', () {
      final menus = result.script.findStatements<RenPyMenuStatement>((_) => true);
      expect(menus.first.items.length, equals(2));
    });

    test('nested menu inside first choice parsed correctly', () {
      final topMenu      = result.script.findStatements<RenPyMenuStatement>((_) => true).first;
      final nestedMenus  = topMenu.items.first.block.whereType<RenPyMenuStatement>().toList();
      expect(nestedMenus, isNotEmpty);
      expect(nestedMenus.first.items.length, equals(2));
    });

    test('scene/show statements record "with" transition', () {
      final sceneS2 = result.script
          .findStatements<RenPySceneStatement>((s) => s.imageName == 'S2')
          .single;
      expect(sceneS2.withExpression, equals('dissolve'));

      final showS3 = result.script
          .findStatements<RenPyShowStatement>((s) => s.imageName == 'S3')
          .single;
      expect(showS3.withExpression, equals('dissolve'));
    });

    test('show statements *without* transition are still parsed', () {
      final showS7 = result.script
          .findStatements<RenPyShowStatement>((s) => s.imageName == 'S7');
      expect(showS7.length, 1);
      expect(showS7.first.withExpression, isNull);
    });

    test('Thoughts and Riley dialogue parsed correctly', () {
      final thoughtsLines = result.script
          .findStatements<RenPySayStatement>((s) => s.character == 'Thoughts');
      expect(thoughtsLines.length, greaterThan(5));  // Plenty of lines.

      final rileyLine = result.script
          .findStatements<RenPySayStatement>((s) => s.character == 'Riley');
      expect(rileyLine.length, 1);
      expect(rileyLine.first.text, contains('Huh?'));
    });

    test('play-sound statements recognised', () {
      final plays = result.script.findStatements<RenPyPlayStatement>((_) => true);
      expect(plays, isNotEmpty);
      expect(plays.every((p) => p.channel == 'sound'), isTrue);
    });

    test('simple "=" assignment captured as DefineStatement', () {
      final defines = result.script
          .findStatements<RenPyDefineStatement>((_) => true);
      expect(defines.any((d) => d.name == 'AyyNoticed1'), isTrue);
    });

    test('"+=" compound assignment captured as PythonStatement', () {
      final pyLines = result.script
          .findStatements<RenPyPythonStatement>((_) => true);
      expect(pyLines.any((p) => p.code.contains('AyyInfo.L += 1')), isTrue);
    });
  });
}
