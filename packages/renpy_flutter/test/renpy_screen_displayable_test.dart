import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('an interactive bar renders a draggable slider and fires its '
      'action on drag end', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
screen volume():
    bar value 50 range 100 action SetVariable("dragged", True) xsize 200

label start:
    \$ dragged = False
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

    await tester.drag(find.byType(Slider), const Offset(40, 0));
    await tester.pump();

    final probe = controller.resolveScreen('volume');
    expect(probe, isNotNull);
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
              return const AssetImage('missing');
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

    // Hovering swaps to the hover image.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('renpy-imagebutton'))),
    );
    await tester.pump();

    final images =
        tester
            .widgetList<Image>(find.byType(Image))
            .map((i) => i.image)
            .whereType<AssetImage>()
            .toList();
    expect(images, isNotEmpty);
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
