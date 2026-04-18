import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'support/renpy_golden_path_harness.dart';
import 'support/renpy_project_player_harness.dart';

void main() {
  testWidgets(
    'Reference Game 4 keeps placed sprites separated and inside the stage',
    (tester) async {
      final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));

      await tester.pumpWidget(
        MaterialApp(
          home: RenPyProjectPlayer(
            project: project,
            audioPlayback: const RenPyNoOpAudioPlayback(),
          ),
        ),
      );

      final harness = RenPyProjectPlayerHarness(tester);
      await harness.pumpUntilText('Reference Game 4 begins.');
      await harness.pumpPastTransition();

      harness.expectSpriteAnchor('eri', const Offset(160, 600));
      harness.expectSpriteAnchor('enj', const Offset(640, 600));

      final stage = harness.stageRect;
      final eri = harness.spriteImageRect('eri');
      final enj = harness.spriteImageRect('enj');

      expect(eri.top, greaterThanOrEqualTo(stage.top));
      expect(enj.top, greaterThanOrEqualTo(stage.top));
      expect(eri.bottom, lessThanOrEqualTo(stage.bottom));
      expect(enj.bottom, lessThanOrEqualTo(stage.bottom));
      expect(eri.center.dx, lessThan(stage.center.dx));
      expect(enj.center.dx, greaterThan(stage.center.dx));
      expect(eri.overlaps(enj), isFalse);
    },
  );

  testWidgets('Reference Game 4 clears sprites on scene replacement', (
    tester,
  ) async {
    final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          audioPlayback: const RenPyNoOpAudioPlayback(),
        ),
      ),
    );

    final harness = RenPyProjectPlayerHarness(tester);
    await harness.pumpUntilText('Reference Game 4 begins.');
    await harness.pumpPastTransition();
    expect(harness.spriteCount('eri'), 1);
    expect(harness.spriteCount('enj'), 1);
    expect(harness.spriteCount('sha'), 0);

    await harness.pumpUntilText(
      'Grayscale flashbacks, multiple characters, and layered placement are active.',
      attempts: 120,
    );
    await harness.pumpPastTransition();

    expect(harness.spriteCount('eri'), 1);
    expect(harness.spriteCount('enj'), 1);
    expect(harness.spriteCount('sha'), 0);
    final eri = harness.spriteImageRect('eri');
    final enj = harness.spriteImageRect('enj');
    expect(eri.center.dx, lessThan(enj.center.dx));
    expect(eri.overlaps(enj), isFalse);
  });

  testWidgets('Reference Game 4 show text displayable is centered and clears', (
    tester,
  ) async {
    final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          audioPlayback: const RenPyNoOpAudioPlayback(),
        ),
      ),
    );

    final harness = RenPyProjectPlayerHarness(tester);
    await harness.pumpUntilSprite('title', attempts: 120);
    await harness.pumpPastTransition();

    harness.expectSpriteAnchor('title', const Offset(400, 300));
    final title = tester.getRect(find.byKey(const ValueKey('title')));
    expect((title.center.dx - harness.stageRect.center.dx).abs(), lessThan(60));

    await tester.tapAt(tester.getCenter(find.byType(RenPyProjectPlayer)));
    await harness.pumpUntilTextGone('Reference Game 4', attempts: 120);
    await harness.pumpPastTransition();
    expect(find.byKey(const ValueKey('title')), findsNothing);
  });

  testWidgets('Reference Game 4 renders deterministic calibration colors', (
    tester,
  ) async {
    final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));
    final captureKey = GlobalKey();
    final background = await _createSolidImage(16, 16, Colors.black);
    final sprite = await _createSolidImage(160, 160, const Color(0xFFFF0000));
    final controller = RenPyFlutterController();

    addTearDown(() {
      background.dispose();
      sprite.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: RepaintBoundary(
            key: captureKey,
            child: RenPyImageLayer(
              controller: controller,
              screenSize: project.screenSize,
              imageProvider: (assetPath) {
                return _FixedSizeImageProvider(
                  assetPath,
                  assetPath.contains('/characters/') ? sprite : background,
                );
              },
            ),
          ),
        ),
      ),
    );

    controller.load(
      project.scriptSource,
      filename: project.scriptPath,
      gameRoot: project.gameRoot,
      availableAssets: project.availableAssets,
    );
    await _pumpControllerUntil(tester, controller, (status) {
      return status is RenPyDialogue &&
          status.displayText.contains('Reference Game 4 begins.');
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    final frame = await _capture(tester, captureKey);
    expect(frame.pixelAt(160, 550), _nearColor(const Color(0xFFFF0000)));
    expect(frame.pixelAt(640, 550), _nearColor(const Color(0xFFFF0000)));
    expect(frame.pixelAt(400, 550), _nearColor(Colors.black));
    expect(frame.pixelAt(400, 200), _nearColor(Colors.black));
  });
}

Future<void> _pumpControllerUntil(
  WidgetTester tester,
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate, {
  int attempts = 100,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    final status = controller.value;
    if (predicate(status)) return;
    switch (status) {
      case RenPyDialogue() || RenPyPause():
        controller.continueGame();
      case RenPyMenu(:final onChoice):
        onChoice(0);
      case _:
        break;
    }
  }

  fail('Controller did not reach expected status. Last: ${controller.value}');
}

Future<_CapturedFrame> _capture(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final frame = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final width = image.width;
    final height = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return _CapturedFrame(
      width: width,
      height: height,
      rgba: data!.buffer.asUint8List(),
    );
  });
  return frame!;
}

final class _CapturedFrame {
  const _CapturedFrame({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final List<int> rgba;

  Color pixelAt(int x, int y) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    final offset = ((y * width) + x) * 4;
    return Color.fromARGB(
      rgba[offset + 3],
      rgba[offset],
      rgba[offset + 1],
      rgba[offset + 2],
    );
  }
}

Matcher _nearColor(Color expected, {int tolerance = 2}) {
  return predicate<Color>((actual) {
    return (actual.a255 - expected.a255).abs() <= tolerance &&
        (actual.r255 - expected.r255).abs() <= tolerance &&
        (actual.g255 - expected.g255).abs() <= tolerance &&
        (actual.b255 - expected.b255).abs() <= tolerance;
  }, 'within $tolerance channels of $expected');
}

Future<ui.Image> _createSolidImage(int width, int height, Color color) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(width, height);
}

class _FixedSizeImageProvider extends ImageProvider<_FixedSizeImageProvider> {
  const _FixedSizeImageProvider(this.assetPath, this.image);

  final String assetPath;
  final ui.Image image;

  @override
  Future<_FixedSizeImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_FixedSizeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FixedSizeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _FixedSizeImageProvider &&
        other.assetPath == assetPath &&
        other.image == image;
  }

  @override
  int get hashCode => Object.hash(assetPath, image);
}

extension on Color {
  int get a255 => (a * 255).round();
  int get r255 => (r * 255).round();
  int get g255 => (g * 255).round();
  int get b255 => (b * 255).round();
}
