import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_spine/renpy_spine.dart';

void main() {
  group('SpineImageName.tryParse', () {
    test('parses <skin>-<group>/<animation>.spine', () {
      expect(
        SpineImageName.tryParse('erikari-movement/idle-front.spine'),
        const SpineImageName(skin: 'erikari', animation: 'movement/idle-front'),
      );
      expect(
        SpineImageName.tryParse('harri-emotes/wave.spine'),
        const SpineImageName(skin: 'harri', animation: 'emotes/wave'),
      );
    });

    test('ignores leading game-root directories', () {
      expect(
        SpineImageName.tryParse(
          'assets/games/1/game/erikari-emotes/angry.spine',
        ),
        const SpineImageName(skin: 'erikari', animation: 'emotes/angry'),
      );
    });

    test('parses bare <skin>-<animation>.spine at the first dash', () {
      expect(
        SpineImageName.tryParse('erikari-angry.spine'),
        const SpineImageName(skin: 'erikari', animation: 'angry'),
      );
      expect(
        SpineImageName.tryParse('erikari-idle-front.spine'),
        const SpineImageName(skin: 'erikari', animation: 'idle-front'),
      );
    });

    test('parses bare <animation>.spine without a skin', () {
      expect(
        SpineImageName.tryParse('wave.spine'),
        const SpineImageName(animation: 'wave'),
      );
    });

    test('a dashless parent directory does not contribute a skin', () {
      expect(
        SpineImageName.tryParse('game/wave.spine'),
        const SpineImageName(animation: 'wave'),
      );
    });

    test('only the immediate parent directory contributes a skin', () {
      expect(
        SpineImageName.tryParse('my-game/poses/wave.spine'),
        const SpineImageName(animation: 'wave'),
      );
    });

    test('extension match is case-insensitive', () {
      expect(
        SpineImageName.tryParse('Erikari-Angry.SPINE'),
        const SpineImageName(skin: 'Erikari', animation: 'Angry'),
      );
    });

    test('rejects non-spine paths', () {
      expect(SpineImageName.tryParse('bg whitehouse.png'), isNull);
      expect(SpineImageName.tryParse('erikari-angry.png'), isNull);
      expect(SpineImageName.tryParse('spine'), isNull);
      expect(SpineImageName.tryParse(''), isNull);
    });

    test('rejects paths with no file name', () {
      expect(SpineImageName.tryParse('.spine'), isNull);
      expect(SpineImageName.tryParse('/.spine'), isNull);
    });

    test('leading or trailing dashes are treated as bare animations', () {
      expect(
        SpineImageName.tryParse('-wave.spine'),
        const SpineImageName(animation: '-wave'),
      );
      expect(
        SpineImageName.tryParse('wave-.spine'),
        const SpineImageName(animation: 'wave-'),
      );
    });
  });
}
