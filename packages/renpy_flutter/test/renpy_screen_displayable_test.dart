import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('an interactive bar writes the dragged value back to its bound '
      'variable as it moves', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    // The bar starts at 0; dragging it rewrites `vol` through the Set action.
    // A sibling text reads `vol` back so we can assert the value actually moved.
    controller.load('''
screen volume():
    vbox:
        bar value vol range 100 action SetVariable("vol", vol) xsize 400
        text "vol=[vol]"

label start:
    \$ vol = 0
    show screen volume
    "playing"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.byType(Slider), findsOneWidget);
    // Starts at zero.
    expect(find.text('vol=0'), findsOneWidget);

    // Drag the slider thumb (at the far left, since the value is 0) to the
    // right. Anchoring on the thumb makes the drag move it continuously.
    final topLeft = tester.getTopLeft(find.byType(Slider));
    final size = tester.getSize(find.byType(Slider));
    final gesture = await tester.startGesture(
      Offset(topLeft.dx + 12, topLeft.dy + size.height / 2),
    );
    await gesture.moveBy(const Offset(250, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // The bound variable changed: it is no longer 0 and is now > 0.
    expect(find.text('vol=0'), findsNothing);
    final readBack = controller.resolveScreen('volume');
    expect(readBack, isNotNull);
    final label = _textValues(
      readBack!,
    ).firstWhere((t) => t.startsWith('vol='), orElse: () => 'vol=?');
    final newValue = int.tryParse(label.substring('vol='.length)) ?? -1;
    expect(newValue, greaterThan(0));
  });

  testWidgets('a non-interactive bar falls back to a progress indicator', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen hp():
    bar value 30 range 100 xsize 200

label start:
    show screen hp
    "playing"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('a timer fires its action after the delay', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen autoclose():
    timer 1.0 action Hide("autoclose")

label start:
    show screen autoclose
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(controller.shownScreens, hasLength(1));

    // Before the delay the screen is still shown.
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.shownScreens, hasLength(1));

    // After the delay the timer fires Hide, removing the screen.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(controller.shownScreens, isEmpty);
  });

  testWidgets('an imagebutton swaps idle/hover images on hover', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen menu_button():
    imagebutton idle "idle.png" hover "hover.png" action Return("ok")

label start:
    show screen menu_button
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    final resolved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenPyScreenLayer(
            controller: controller,
            imageProvider: (asset) {
              resolved.add(asset);
              return AssetImage(asset);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // The idle and hover images are both prepared.
    expect(resolved, contains('idle.png'));
    expect(resolved, contains('hover.png'));
    expect(find.byKey(const ValueKey('renpy-imagebutton')), findsOneWidget);

    // Before hover the displayed image is the idle asset, not the hover asset.
    expect(_displayedAssets(tester), equals(['idle.png']));

    // Hovering swaps the displayed image to the hover asset.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('renpy-imagebutton'))),
    );
    await tester.pump();

    expect(_displayedAssets(tester), equals(['hover.png']));
  });

  testWidgets('an imagebutton shows the selected image over the idle image', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen tab():
    imagebutton idle "off.png" selected_idle "on.png" selected True action NullAction()

label start:
    show screen tab
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    // `selected True` swaps the idle image to the selected_idle asset.
    expect(_displayedAssets(tester), equals(['on.png']));
  });

  testWidgets('side places children into a positional layout', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen layout():
    side "c t b":
        text "center"
        text "top"
        text "bottom"

label start:
    show screen layout
    "waiting"
''');

    await _drainUntil(controller, () => controller.value is RenPyDialogue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RenPyScreenLayer(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('renpy-side')), findsOneWidget);
    expect(find.text('center'), findsOneWidget);
    expect(find.text('top'), findsOneWidget);
    expect(find.text('bottom'), findsOneWidget);

    // The top child is positioned above the bottom child.
    final topY = tester.getCenter(find.text('top')).dy;
    final bottomY = tester.getCenter(find.text('bottom')).dy;
    expect(topY, lessThan(bottomY));
  });
}

/// The asset names of every [Image] currently rendered, in tree order.
List<String> _displayedAssets(WidgetTester tester) {
  return tester
      .widgetList<Image>(find.byType(Image))
      .map((i) => i.image)
      .whereType<AssetImage>()
      .map((a) => a.assetName)
      .toList();
}

/// Collects every resolved text node's interpolated string from a screen tree.
List<String> _textValues(RenPyResolvedScreen screen) {
  final out = <String>[];
  void walk(List<RenPyResolvedDisplayable> nodes) {
    for (final node in nodes) {
      final text = node.interpolatedText ?? node.text;
      if (text != null) out.add(text);
      walk(node.children);
    }
  }

  walk(screen.children);
  return out;
}

Future<void> _drainUntil(
  RenPyFlutterController controller,
  bool Function() done,
) async {
  for (var i = 0; i < 100; i += 1) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Controller did not reach expected state. Last: ${controller.value}');
}
