import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('RenPyImageResolver', () {
    test('resolves explicit image aliases from a script', () {
      final script =
          RenPyParser().parse('''
init:
    image bg lecturehall = "lecture hall.jpg"
    image eileen happy = Image("sprites/eileen happy.png")
''', 'script.rpy').script;

      final resolver = RenPyImageResolver.fromScript(
        script,
        assetRoot: 'assets/game',
        availableAssets: const {
          'assets/game/images/lecture hall.jpg',
          'assets/game/sprites/eileen happy.png',
        },
      );

      expect(
        resolver.resolve('bg lecturehall'),
        'assets/game/images/lecture hall.jpg',
      );
      expect(
        resolver.resolve('eileen happy'),
        'assets/game/sprites/eileen happy.png',
      );
    });

    test('resolves implicit image names using spaces and underscores', () {
      final resolver = RenPyImageResolver(
        assetRoot: 'assets/game',
        availableAssets: const {
          'assets/game/images/bg uni.jpg',
          'assets/game/images/sylvie_green_normal.png',
        },
      );

      expect(resolver.resolve('bg uni'), 'assets/game/images/bg uni.jpg');
      expect(
        resolver.resolve('sylvie green normal # dissolve'),
        'assets/game/images/sylvie_green_normal.png',
      );
    });

    test('treats black as a scene clear rather than an asset', () {
      final resolver = RenPyImageResolver(
        assetRoot: 'assets/game',
        availableAssets: const {
          'assets/game/images/black.png',
          'assets/game/images/white.png',
        },
      );

      expect(resolver.resolve('black'), isNull);
      expect(resolver.resolve('white'), isNull);
      expect(resolver.resolve(null), isNull);
    });

    test('resolves displayable wrapper aliases to their source assets', () {
      final script =
          RenPyParser().parse('''
init:
    image fea_l8bw = im.Grayscale("/bg/fea_l8.jpg")
    image enj defa1bw = im.MatrixColor("/characters/enj/1/enj defa1.png", im.matrix.tint(1.0, 0.75, 0.75))
''', 'script.rpy').script;

      final resolver = RenPyImageResolver.fromScript(
        script,
        assetRoot: 'game',
        availableAssets: const {
          'game/images/bg/fea_l8.jpg',
          'game/images/characters/enj/1/enj defa1.png',
        },
      );

      expect(resolver.resolve('fea_l8bw'), 'game/images/bg/fea_l8.jpg');
      expect(
        resolver.resolve('enj defa1bw'),
        'game/images/characters/enj/1/enj defa1.png',
      );
    });

    test('preserves displayable operation intent for image aliases', () {
      final script =
          RenPyParser().parse('''
init:
    image fea_l8bw = im.Grayscale("/bg/fea_l8.jpg")
    image beach_s = im.Sepia("/bg/beach.jpg")
    image sha flipped = im.Flip("/characters/sha.png", horizontal=True)
    image red bg = im.MatrixColor("/bg/mlib.jpg", im.matrix.tint(1.0, 0.5, 0.25))
''', 'script.rpy').script;

      final resolver = RenPyImageResolver.fromScript(
        script,
        assetRoot: 'game',
        availableAssets: const {
          'game/images/bg/fea_l8.jpg',
          'game/images/bg/beach.jpg',
          'game/images/characters/sha.png',
          'game/images/bg/mlib.jpg',
        },
      );

      expect(
        resolver.resolveImage('fea_l8bw'),
        const RenPyResolvedImage(
          assetPath: 'game/images/bg/fea_l8.jpg',
          operations: [RenPyImageOperation.grayscale()],
        ),
      );
      expect(resolver.resolveImage('beach_s')?.operations, const [
        RenPyImageOperation.sepia(),
      ]);
      expect(resolver.resolveImage('sha flipped')?.operations, const [
        RenPyImageOperation.flipHorizontal(),
      ]);
      expect(resolver.resolveImage('red bg')?.operations, const [
        RenPyImageOperation.matrixColor(
          tintRed: 1,
          tintGreen: 0.5,
          tintBlue: 0.25,
        ),
      ]);
    });

    test('registers runtime image aliases explicitly', () {
      final script =
          RenPyParser().parse('''
label start:
    image flashback bg = im.Grayscale("/bg/flashback.jpg")
    scene flashback bg
''', 'script.rpy').script;

      final resolver = RenPyImageResolver.fromScript(
        script,
        assetRoot: 'game',
        availableAssets: const {'game/images/bg/flashback.jpg'},
      );

      expect(resolver.resolve('flashback bg'), 'game/flashback bg.png');

      final updated = resolver.withImageAlias(
        'flashback bg',
        'im.Grayscale("/bg/flashback.jpg")',
      );
      expect(updated.resolve('flashback bg'), 'game/images/bg/flashback.jpg');
    });

    test('resolves nested RenPy image assets by basename', () {
      final resolver = RenPyImageResolver(
        assetRoot: 'game',
        availableAssets: const {
          'game/images/bg/fea_l4.jpg',
          'game/images/characters/enj/1/enj fumana2.png',
        },
      );

      expect(resolver.resolve('fea_l4'), 'game/images/bg/fea_l4.jpg');
      expect(
        resolver.resolve('enj fumana2'),
        'game/images/characters/enj/1/enj fumana2.png',
      );
    });

    test(
      'returns the first conventional candidate when no manifest is known',
      () {
        final resolver = RenPyImageResolver(assetRoot: 'assets/game');

        expect(
          resolver.resolve('missing pose'),
          'assets/game/missing pose.png',
        );
      },
    );
  });
}
