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
        availableAssets: const {'assets/game/images/black.png'},
      );

      expect(resolver.resolve('black'), isNull);
      expect(resolver.resolve(null), isNull);
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
