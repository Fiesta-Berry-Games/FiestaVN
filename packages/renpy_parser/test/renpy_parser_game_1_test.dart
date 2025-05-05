import 'dart:io';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Reference Game 1 tests', () {
    late RenPyParser parser;
    late RenPyParseResult result;
    late String scriptContent;

    setUp(() async {
      parser = RenPyParser();

      // Load the test script file.
      final file = File('test/games/1/game/script.rpy');
      scriptContent = await file.readAsString();

      // Parse the script.
      result = parser.parse(scriptContent, 'script.rpy');
    });

    test('Script should parse without errors or warnings', () {
      // Verify parsing succeeded and there are no warnings.
      expect(result.script.statements, isNotEmpty);
      expect(result.warnings, isEmpty);
    });

    test('Init block should be correctly parsed', () {
      // Find all init statements
      final initStatements = result.script.findStatements<RenPyInitStatement>(
        (stmt) => true,
      );

      // There should be one init block.
      expect(initStatements.length, 1);

      // The init block should contain 3 image statements.
      final firstInit = initStatements.first;
      final imageStatementsInInit =
          firstInit.block.whereType<RenPyImageStatement>().toList();
      expect(imageStatementsInInit.length, 3);
    });

    test('Image statements should be correctly parsed', () {
      // Find all image statements.
      final imageStatements = result.script.findStatements<RenPyImageStatement>(
        (stmt) => true,
      );

      // There should be 3 image statements.
      expect(imageStatements.length, 3);

      // Verify the image names and expressions.
      expect(imageStatements.map((e) => e.name).toList()..sort(), [
        'eileen happy',
        'eileen upset',
        'whitehouse',
      ]);

      expect(imageStatements.map((e) => e.expression).toList()..sort(), [
        'Image("eileen_happy.png")',
        'Image("eileen_upset.png")',
        'Image("whitehouse.jpg")',
      ]);
    });

    test('Label statements should be correctly parsed', () {
      // Find all label statements.
      final labels = result.script.labels;

      // There should be 1 label
      expect(labels.length, 1);
      expect(labels.keys, contains('start'));

      // The start label should contain multiple statements.
      final startLabel = labels['start']!;
      expect(startLabel.block.length, greaterThan(1));
    });

    test('Character definition should be correctly parsed', () {
      // Find all define statements
      final defineStatements = result.script
          .findStatements<RenPyDefineStatement>((stmt) => true);

      // There should be one character definition.
      expect(defineStatements.length, 1);
      expect(defineStatements.first.name, 'e');
      expect(defineStatements.first.expression, "Character('Eileen')");

      // Check the character map as well.
      final characters = result.script.characters;
      expect(characters.length, 1);
      expect(characters.keys, contains('e'));
    });

    test('Scene statements should be correctly parsed', () {
      // Find all scene statements.
      final sceneStatements = result.script.findStatements<RenPySceneStatement>(
        (stmt) => true,
      );

      // There should be one scene statement.
      expect(sceneStatements.length, 1);
      expect(sceneStatements.first.imageName, 'whitehouse');
      expect(sceneStatements.first.atExpression, null);
      expect(sceneStatements.first.withExpression, null);
    });

    test('Show statements should be correctly parsed', () {
      // Find all show statements.
      final showStatements = result.script.findStatements<RenPyShowStatement>(
        (stmt) => true,
      );

      // There should be two show statements.
      expect(showStatements.length, 2);

      // Verify the image names
      final imageNames =
          showStatements.map((e) => e.imageName).toList()..sort();
      expect(imageNames, ['eileen happy', 'eileen upset']);

      // All show statements should have null atExpression and withExpression.
      for (final stmt in showStatements) {
        expect(stmt.atExpression, null);
        expect(stmt.withExpression, null);
      }
    });

    test('Say statements with character should be correctly parsed', () {
      // Find all say statements with character 'e'.
      final sayStatementsWithE = result.script
          .findStatements<RenPySayStatement>((stmt) => stmt.character == 'e');

      // There should be 3 say statements with character 'e'.
      expect(sayStatementsWithE.length, 3);

      // Verify the dialogue content.
      final dialogueTexts = sayStatementsWithE.map((e) => e.text).toList();
      expect(
        dialogueTexts,
        contains("I'm standing in front of the White House."),
      );
      expect(
        dialogueTexts,
        contains(contains("I once wanted to go on a tour of the West Wing")),
      );
      expect(dialogueTexts, contains(contains("I considered sneaking in")));

      // Test multiline dialogue is preserved
      expect(dialogueTexts.any((text) => text!.contains('\n')), isTrue);
    });

    test('Narrator say statements should be correctly parsed', () {
      // Find all say statements without a character (narrator).
      final narratorStatements = result.script
          .findStatements<RenPySayStatement>((stmt) => stmt.character == null);

      // There should be one narrator statement
      expect(narratorStatements.length, 1);
      expect(
        narratorStatements.first.text,
        contains('For some reason, she really seems upset about this.'),
      );
    });

    test('Statement ordering should be preserved', () {
      // Get all statements in the start label.
      final startLabel = result.script.labels['start']!;
      final statements = startLabel.block;

      // Define the expected order of statement types.
      final expectedTypes = [
        RenPyDefineStatement, // $ e = Character('Eileen')
        RenPySceneStatement, // scene whitehouse
        RenPyShowStatement, // show eileen happy
        RenPySayStatement, // e "I'm standing..."
        RenPyShowStatement, // show eileen upset
        RenPySayStatement, // e "I once wanted..."
        RenPySayStatement, // "For some reason..."
        RenPySayStatement, // e "I considered..."
      ];

      // Verify the actual order matches the expected order
      for (int i = 0; i < expectedTypes.length; i++) {
        expect(
          statements[i].runtimeType,
          expectedTypes[i],
          reason: 'Statement at index $i should be ${expectedTypes[i]}',
        );
      }
    });

    test('Multiline dialogue should be preserved with whitespace', () {
      // Find the multiline dialogue.
      final multilineDialogue =
          result.script
              .findStatements<RenPySayStatement>(
                (stmt) => stmt.text?.contains('\n') ?? false,
              )
              .first;

      // Verify the exact content of the multiline dialogue.
      expect(
        multilineDialogue.text,
        "I once wanted to go on a tour of the West Wing, but you have to\n       know somebody to get in.",
      );

      // Make sure the original indentation is preserved.
      expect(multilineDialogue.text, contains('\n       '));
    });

    test(
      'Dollar-sign character definition should be parsed as a DefineStatement',
      () {
        // In the script.rpy file, $ e = Character('Eileen') is parsed as a DefineStatement, not as a PythonStatement.
        // This appears to be how the parser is implemented in RenPyParser._parseStatement.
        final defineStatements = result.script
            .findStatements<RenPyDefineStatement>((stmt) => true);

        // There should be one character definition.
        expect(defineStatements.length, 1);
        expect(defineStatements.first.name, 'e');
        expect(defineStatements.first.expression, "Character('Eileen')");
      },
    );

    test('Script structure should match the original code', () {
      // The script should have two top-level statements: init block and start label.
      expect(result.script.statements.length, 2);
      expect(result.script.statements[0], isA<RenPyInitStatement>());
      expect(result.script.statements[1], isA<RenPyLabelStatement>());

      // The init block should have 3 image statements.
      final initBlock = result.script.statements[0] as RenPyInitStatement;
      expect(initBlock.block.length, 3);
      expect(
        initBlock.block.every((stmt) => stmt is RenPyImageStatement),
        isTrue,
      );

      // The start label should have 8 statements.
      final startLabel = result.script.statements[1] as RenPyLabelStatement;
      expect(startLabel.block.length, 8);
    });
  });
}
