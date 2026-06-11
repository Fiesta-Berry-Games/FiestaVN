import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

const String story = '''
image logo = "presplash.png"

play music "audio/menu_theme.ogg"
scene bg menu

label start:
    scene bg meadow
    play music "audio/illurock.ogg"
    show sylvie green smile
    voice "voice/line_001.ogg"
    "Shall we explore?"
    menu:
        "Yes":
            show sylvie green surprised
            play sound "audio/effects/chime.ogg"
        "No":
            show sylvie green smile
    show sylvie green smile
    jump ending

label ending:
    scene bg lecturehall
    if True:
        show logo
    queue music "audio/menu_theme.ogg"
    return
''';

const Set<String> manifest = {
  'game/images/presplash.png',
  'game/images/bg menu.png',
  'game/images/bg meadow.png',
  'game/images/bg lecturehall.png',
  'game/images/sylvie green smile.png',
  'game/images/sylvie green surprised.png',
  'game/audio/menu_theme.ogg',
  'game/audio/illurock.ogg',
  'game/audio/effects/chime.ogg',
  'game/voice/line_001.ogg',
};

RenPyAssetPlan planFor(
  String source, {
  Set<String> availableAssets = manifest,
}) {
  final script = RenPyParser().parse(source, 'script.rpy').script;
  return RenPyAssetPlan.fromScript(
    script,
    resolver: RenPyImageResolver.fromScript(
      script,
      assetRoot: 'game',
      availableAssets: availableAssets,
    ),
    availableAssets: availableAssets,
    gameRoot: 'game',
  );
}

void main() {
  group('RenPyAssetPlan.fromScript', () {
    test('segments a script into a preamble plus one segment per label', () {
      final plan = planFor(story);

      expect(plan.segments, hasLength(3));
      expect(plan.segments.map((segment) => segment.label), [
        null,
        'start',
        'ending',
      ]);
    });

    test('preamble collects pre-label scene/show/play references', () {
      final plan = planFor(story);

      expect(plan.segments.first.label, isNull);
      expect(plan.segments.first.assets, [
        'game/audio/menu_theme.ogg',
        'game/images/bg menu.png',
      ]);
    });

    test('omits the preamble segment when it references no assets', () {
      final plan = planFor('''
define e = Character("Eileen")

label start:
    scene bg meadow
''');

      expect(plan.segments, hasLength(1));
      expect(plan.segments.single.label, 'start');
      expect(plan.segments.single.assets, ['game/images/bg meadow.png']);
    });

    test('records assets in first-reference order, deduped per segment', () {
      final plan = planFor(story);
      final start = plan.segments[plan.segmentIndexForLabel('start')];

      // `sylvie green smile` is shown three times (twice at the top level,
      // once inside a menu choice) but recorded once, at its first position.
      expect(start.assets, [
        'game/images/bg meadow.png',
        'game/audio/illurock.ogg',
        'game/images/sylvie green smile.png',
        'game/voice/line_001.ogg',
        'game/images/sylvie green surprised.png',
        'game/audio/effects/chime.ogg',
      ]);
    });

    test('descends into menu choices and if branches', () {
      final plan = planFor(story);

      // `sylvie green surprised` and the chime live only inside menu
      // choices; the logo show lives only inside an `if` branch.
      final start = plan.segments[plan.segmentIndexForLabel('start')];
      expect(
        start.assets,
        containsAll([
          'game/images/sylvie green surprised.png',
          'game/audio/effects/chime.ogg',
        ]),
      );
      final ending = plan.segments[plan.segmentIndexForLabel('ending')];
      expect(ending.assets, [
        'game/images/bg lecturehall.png',
        'game/images/presplash.png',
        'game/audio/menu_theme.ogg',
      ]);
    });

    test('descends into while and for loop bodies', () {
      final plan = planFor('''
label start:
    while not done:
        show sylvie green smile
        for q in questions:
            play sound "audio/effects/chime.ogg"
''');

      expect(plan.segments.single.assets, [
        'game/images/sylvie green smile.png',
        'game/audio/effects/chime.ogg',
      ]);
    });

    test('filters assets that are not in availableAssets', () {
      final plan = planFor('''
label start:
    scene bg missing
    show sylvie green smile
    play music "audio/missing.ogg"
''');

      expect(plan.segments.single.assets, [
        'game/images/sylvie green smile.png',
      ]);
    });

    test('records every speculative path when availableAssets is empty', () {
      final plan = planFor('''
label start:
    play music "audio/illurock.ogg"
''', availableAssets: const {});

      expect(plan.segments.single.assets, ['game/audio/illurock.ogg']);
    });

    test('skips solid colors and dynamic audio expressions', () {
      final plan = planFor('''
image flash = Solid("#fff")

label start:
    scene black
    show flash
    play music current_track
    voice sustain
    show sylvie green smile
''');

      expect(plan.segments.single.assets, [
        'game/images/sylvie green smile.png',
      ]);
    });

    test('normalizes audio paths like the flutter audio asset resolver', () {
      final plan = planFor(r'''
label start:
    play music "audio\illurock.ogg"
    play sound "/audio/effects/chime.ogg"
    voice "assets/voice/line_001.ogg"
''', availableAssets: const {});

      expect(plan.segments.single.assets, [
        'game/audio/illurock.ogg',
        'game/audio/effects/chime.ogg',
        'assets/voice/line_001.ogg',
      ]);
    });

    test('keeps segment line numbers from the source', () {
      final plan = planFor(story);

      expect(
        plan.segments[0].linenumber,
        lessThan(plan.segments[1].linenumber),
      );
      expect(
        plan.segments[1].linenumber,
        lessThan(plan.segments[2].linenumber),
      );
    });
  });

  group('RenPyAssetPlan queries', () {
    test('allAssets is the union of every segment', () {
      final plan = planFor(story);

      expect(plan.allAssets, {
        'game/audio/menu_theme.ogg',
        'game/images/bg menu.png',
        'game/images/bg meadow.png',
        'game/audio/illurock.ogg',
        'game/images/sylvie green smile.png',
        'game/voice/line_001.ogg',
        'game/images/sylvie green surprised.png',
        'game/audio/effects/chime.ogg',
        'game/images/bg lecturehall.png',
        'game/images/presplash.png',
      });
    });

    test('assetsFromSegment flattens and dedupes from the index onward', () {
      final plan = planFor(story);

      // From `ending` onward only its own assets remain.
      expect(plan.assetsFromSegment(plan.segmentIndexForLabel('ending')), [
        'game/images/bg lecturehall.png',
        'game/images/presplash.png',
        'game/audio/menu_theme.ogg',
      ]);

      // From `start` onward, `audio/menu_theme.ogg` appears in both `start`'s
      // future (`ending` queues it) and is kept once, at its first position.
      final fromStart = plan.assetsFromSegment(
        plan.segmentIndexForLabel('start'),
      );
      expect(fromStart, [
        'game/images/bg meadow.png',
        'game/audio/illurock.ogg',
        'game/images/sylvie green smile.png',
        'game/voice/line_001.ogg',
        'game/images/sylvie green surprised.png',
        'game/audio/effects/chime.ogg',
        'game/images/bg lecturehall.png',
        'game/images/presplash.png',
        'game/audio/menu_theme.ogg',
      ]);

      // From the beginning the plan covers everything, preamble first.
      expect(plan.assetsFromSegment(0).toSet(), plan.allAssets);
      expect(plan.assetsFromSegment(0).first, 'game/audio/menu_theme.ogg');
    });

    test('assetsFromSegment clamps out-of-range indices', () {
      final plan = planFor(story);

      expect(plan.assetsFromSegment(-1), plan.assetsFromSegment(0));
      expect(plan.assetsFromSegment(plan.segments.length), isEmpty);
    });

    test('segmentIndexForLabel finds top-level labels only', () {
      final plan = planFor(story);

      expect(plan.segmentIndexForLabel('start'), 1);
      expect(plan.segmentIndexForLabel('ending'), 2);
      expect(plan.segmentIndexForLabel('nope'), -1);
    });

    test('segments and their asset lists are unmodifiable', () {
      final plan = planFor(story);

      expect(() => plan.segments.removeLast(), throwsUnsupportedError);
      expect(() => plan.segments.first.assets.add('x'), throwsUnsupportedError);
    });
  });
}
