import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

final class RenPyProjectPlayerHarness {
  const RenPyProjectPlayerHarness(this.tester);

  final WidgetTester tester;

  List<ImageProvider<Object>> get imageProviders {
    return tester.widgetList<Image>(find.byType(Image)).map((image) {
      return image.image;
    }).toList();
  }

  int get memoryImageCount {
    return imageProviders.whereType<MemoryImage>().length;
  }

  List<Color> get stageColors {
    final stage = find.byKey(const ValueKey('renpy-stage-color'));
    if (stage.evaluate().isEmpty) return const [];
    return tester
        .widgetList<ColoredBox>(stage)
        .map((box) => box.color)
        .toList();
  }

  Future<void> pumpUntilText(String text, {int attempts = 50}) async {
    await pumpUntil(
      () => find.textContaining(text).evaluate().isNotEmpty,
      attempts: attempts,
      description: 'text containing "$text"',
    );
  }

  Future<void> pumpUntilTextGone(String text, {int attempts = 50}) async {
    await pumpUntil(
      () => find.textContaining(text).evaluate().isEmpty,
      attempts: attempts,
      description: 'text containing "$text" to disappear',
    );
  }

  Future<void> pumpUntilSprite(String tag, {int attempts = 50}) async {
    await pumpUntil(
      () => find.byKey(ValueKey(tag)).evaluate().isNotEmpty,
      attempts: attempts,
      description: 'sprite "$tag"',
    );
  }

  Future<void> pumpPastTransition([
    Duration duration = const Duration(seconds: 3),
  ]) async {
    await tester.pump(duration);
  }

  Future<void> pumpUntilImages({int attempts = 50}) async {
    await pumpUntil(
      () => find.byType(Image).evaluate().isNotEmpty,
      attempts: attempts,
      description: 'archived images',
    );
  }

  Future<void> pumpUntilTitleCard({int attempts = 700}) async {
    await pumpUntil(
      () {
        final titleVisible =
            find
                .textContaining('Confession of the Golden Witch')
                .evaluate()
                .length;
        return titleVisible >= 1 &&
            stageColors.contains(const Color(0xFFFF0000));
      },
      attempts: attempts,
      description: 'red title card',
    );
  }

  Future<void> pumpUntil(
    bool Function() condition, {
    required String description,
    int attempts = 50,
  }) async {
    for (var i = 0; i < attempts; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (condition()) return;
      await _advanceIfWaiting();
    }

    fail('Timed out waiting for $description.');
  }

  Offset spriteAnchor(String tag) {
    final positioned = tester.widgetList<Positioned>(
      find.descendant(
        of: find.byKey(ValueKey(tag)),
        matching: find.byType(Positioned),
      ),
    );
    final anchor = positioned.lastWhere(
      (widget) =>
          widget.left != null && widget.top != null && widget.right == null,
    );
    return Offset(anchor.left!, anchor.top!);
  }

  int spriteCount(String tag) {
    return find.byKey(ValueKey(tag)).evaluate().length;
  }

  Rect spriteImageRect(String tag) {
    return tester.getRect(
      find.descendant(
        of: find.byKey(ValueKey(tag)),
        matching: find.byType(Image),
      ),
    );
  }

  Rect get stageRect {
    return tester.getRect(find.byType(RenPyProjectPlayer));
  }

  void expectSpriteAnchor(String tag, Offset expected) {
    final actual = spriteAnchor(tag);
    expect(actual.dx, closeTo(expected.dx, 0.0001));
    expect(actual.dy, closeTo(expected.dy, 0.0001));
  }

  void expectItalicSpan(String text) {
    final renderedText = tester.widget<Text>(
      find.descendant(of: find.byType(RenPyText), matching: find.byType(Text)),
    );
    final rootSpan = renderedText.textSpan! as TextSpan;
    final spans = rootSpan.children!.cast<TextSpan>();
    expect(
      spans.singleWhere((span) => span.text == text).style?.fontStyle,
      FontStyle.italic,
    );
  }

  Future<void> _advanceIfWaiting() async {
    final firstMenuChoice = find.byKey(const ValueKey('menu_choice_0'));
    if (firstMenuChoice.evaluate().isNotEmpty) {
      await tester.tap(firstMenuChoice);
      return;
    }

    if (find.byType(RenPyPauseView).evaluate().isNotEmpty) {
      await tester.tap(find.byType(RenPyPauseView), warnIfMissed: false);
      return;
    }

    final player = find.byType(RenPyProjectPlayer);
    if (player.evaluate().isNotEmpty) {
      await tester.tapAt(tester.getCenter(player));
    }
  }
}
