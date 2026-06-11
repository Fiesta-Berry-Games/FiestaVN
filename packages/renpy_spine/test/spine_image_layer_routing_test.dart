import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_spine/renpy_spine.dart';

const _erikari = SpineCharacter(
  tag: 'erikari',
  atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
  skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
  defaultSkin: 'erikari',
  idleAnimation: 'movement/idle-front',
);

const _charactersByTag = {'erikari': _erikari};

void main() {
  group('classifySpineShow', () {
    test('routes a .spine asset with a matching tag to Spine', () {
      final route = classifySpineShow(
        show: 'erikari angry',
        assetPath: 'game/erikari-emotes/angry.spine',
        charactersByTag: _charactersByTag,
      );

      expect(route, isNotNull);
      expect(route!.character, same(_erikari));
      expect(route.tag, 'erikari');
      expect(route.skin, 'erikari');
      expect(route.animation, 'emotes/angry');
    });

    test('falls back to the character default skin for bare animations', () {
      final route = classifySpineShow(
        show: 'erikari wave',
        assetPath: 'game/wave.spine',
        charactersByTag: _charactersByTag,
      );

      expect(route, isNotNull);
      expect(route!.skin, 'erikari');
      expect(route.animation, 'wave');
    });

    test('delegates non-spine assets to the regular layer', () {
      final route = classifySpineShow(
        show: 'erikari photo',
        assetPath: 'game/erikari photo.png',
        charactersByTag: _charactersByTag,
      );

      expect(route, isNull);
    });

    test('delegates .spine assets with unknown tags', () {
      final route = classifySpineShow(
        show: 'stranger wave',
        assetPath: 'game/stranger-emotes/wave.spine',
        charactersByTag: _charactersByTag,
      );

      expect(route, isNull);
    });

    test('delegates shows without a resolved asset', () {
      final route = classifySpineShow(
        show: 'erikari wave',
        assetPath: null,
        charactersByTag: _charactersByTag,
      );

      expect(route, isNull);
    });
  });

  group('routing against a running controller', () {
    test('classifies image changes emitted by a loaded script', () {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      final shows = <RenPyImageChange>[];
      controller.addListener(() {
        final value = controller.value;
        if (value is RenPyImageChange && value.show != null) {
          shows.add(value);
        }
      });

      controller.load('''
init:
    image erikari idle = Image("erikari-movement/idle-front.spine")

label start:
    scene bg whitehouse
    show erikari idle at left
    show eileen happy
    "done"
''', filename: 'script.rpy', gameRoot: 'game');

      expect(shows, hasLength(2));

      final routes = [
        for (final change in shows)
          classifySpineShow(
            show: change.show!,
            assetPath: change.showAsset ?? change.showImage?.assetPath,
            charactersByTag: _charactersByTag,
          ),
      ];

      // `show erikari idle` resolves to a .spine asset and a known tag.
      expect(shows.first.show, 'erikari idle');
      expect(shows.first.showAsset, endsWith('.spine'));
      expect(routes.first, isNotNull);
      expect(routes.first!.tag, 'erikari');
      expect(routes.first!.skin, 'erikari');
      expect(routes.first!.animation, 'movement/idle-front');

      // `show eileen happy` is a regular image: delegated to the fallback.
      expect(shows.last.show, 'eileen happy');
      expect(routes.last, isNull);
    });
  });
}
