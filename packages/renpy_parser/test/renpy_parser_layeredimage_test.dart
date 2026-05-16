import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('layeredimage parsing', () {
    test('parses always + two groups with a default into the model', () {
      final result = RenPyParser().parse('''
layeredimage eileen:
    always:
        "eileen_base"
    group outfit:
        attribute casual default:
            "eileen_casual"
        attribute formal:
            "eileen_formal"
    group face:
        attribute smile:
            "eileen_smile"
        attribute frown:
            "eileen_frown"
''', 'layered.rpy');

      expect(result.warnings, isEmpty);

      final statements = result.script
          .findStatements<RenPyLayeredImageStatement>(
            (stmt) => stmt.name == 'eileen',
          );
      expect(statements, hasLength(1));

      final eileen = statements.single;
      expect(eileen.layers, hasLength(5));

      final always = eileen.layers.first;
      expect(always.kind, RenPyLayeredImageLayerKind.always);
      expect(always.displayable, 'eileen_base');

      final casual = eileen.layers[1];
      expect(casual.kind, RenPyLayeredImageLayerKind.attribute);
      expect(casual.group, 'outfit');
      expect(casual.attribute, 'casual');
      expect(casual.isDefault, isTrue);
      expect(casual.displayable, 'eileen_casual');

      final formal = eileen.layers[2];
      expect(formal.group, 'outfit');
      expect(formal.attribute, 'formal');
      expect(formal.isDefault, isFalse);

      final face = eileen.layers.where((l) => l.group == 'face').toList();
      expect(face.map((l) => l.attribute), containsAll(['smile', 'frown']));
    });

    test('parses an if-condition layer and per-attribute properties', () {
      final result = RenPyParser().parse('''
layeredimage eileen:
    if hungry:
        "eileen_hungry"
    group eyes:
        attribute open default:
            "eileen_open"
            at center
''', 'layered.rpy');

      expect(result.warnings, isEmpty);
      final eileen =
          result.script
              .findStatements<RenPyLayeredImageStatement>(
                (stmt) => stmt.name == 'eileen',
              )
              .single;

      final conditionLayer = eileen.layers.firstWhere(
        (l) => l.kind == RenPyLayeredImageLayerKind.condition,
      );
      expect(conditionLayer.condition, 'hungry');
      expect(conditionLayer.displayable, 'eileen_hungry');

      final open = eileen.layers.firstWhere((l) => l.attribute == 'open');
      expect(open.properties['at'], 'center');
    });

    test('does not regress plain image statements', () {
      final result = RenPyParser().parse('''
image bg room = "room.png"
''', 'image.rpy');

      expect(result.warnings, isEmpty);
      expect(
        result.script.findStatements<RenPyImageStatement>((_) => true),
        hasLength(1),
      );
      expect(
        result.script.findStatements<RenPyLayeredImageStatement>((_) => true),
        isEmpty,
      );
    });
  });
}
