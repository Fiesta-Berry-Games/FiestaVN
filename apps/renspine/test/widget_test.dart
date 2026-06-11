import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_spine/renpy_spine.dart';
import 'package:renspine/main.dart';

void main() {
  testWidgets('launcher lists the Fiesta Skit showcase', (tester) async {
    await tester.pumpWidget(const FiestaVNApp());

    expect(find.text('Choose a demo game'), findsOneWidget);
    expect(find.text('Fiesta Skit - Spine Showcase'), findsOneWidget);
  });

  testWidgets('app builds with the package-provided Spine image layer', (
    tester,
  ) async {
    // Build the same layer GameScreen passes to RenPyAssetPlayer. No script
    // is loaded, so no Spine sprite (and no spine_flutter native runtime) is
    // instantiated: only the routing layer and its default underlay.
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    final buildLayer = spineImageLayerBuilder(characters: kSpineCharacters);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => buildLayer(context, controller)),
      ),
    );

    expect(find.byType(SpineImageLayer), findsOneWidget);
    // The default renpy_flutter layer renders underneath, so non-spine
    // images (scene backgrounds, regular sprites) keep working.
    expect(find.byType(RenPyImageLayer), findsOneWidget);
    expect(find.byType(SpineSpriteWidget), findsNothing);
  });
}
