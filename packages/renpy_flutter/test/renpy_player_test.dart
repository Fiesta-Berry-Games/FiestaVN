import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets(
    'asset player loads a bundled script and renders the first beat',
    (tester) async {
      final bundle = _MemoryAssetBundle({
        'assets/game/script.rpy': '''
label start:
    scene bg lecturehall
    "Welcome to class."
''',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RenPyAssetPlayer(
            scriptAsset: 'assets/game/script.rpy',
            bundle: bundle,
            availableAssets: const {'assets/game/images/bg lecturehall.png'},
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _pumpUntil(tester, find.text('Welcome to class.'));

      expect(find.text('Welcome to class.'), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(
        (images.single.image as AssetImage).assetName,
        'assets/game/images/bg lecturehall.png',
      );
    },
  );

  testWidgets('asset player can restart the loaded script', (tester) async {
    final bundle = _MemoryAssetBundle({
      'assets/game/script.rpy': '''
label start:
    "First."
    "Second."
''',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
          bundle: bundle,
          availableAssets: const {},
        ),
      ),
    );

    await _pumpUntil(tester, find.text('First.'));
    await tester.tap(find.text('First.'));
    await _pumpUntil(tester, find.text('Second.'));

    await tester.tap(find.byTooltip('Restart'));
    await _pumpUntil(tester, find.text('First.'));

    expect(find.text('First.'), findsOneWidget);
    expect(find.text('Second.'), findsNothing);
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }

  fail('Timed out waiting for $finder');
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = assets[key];
    if (value == null) {
      throw FlutterError('Missing test asset: $key');
    }
    return value;
  }

  @override
  Future<ByteData> load(String key) {
    throw UnimplementedError('Binary assets are not used by this test.');
  }
}
