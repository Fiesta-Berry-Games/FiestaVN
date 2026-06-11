import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_spine/renpy_spine.dart';

/// The Spine characters available to the demo games' `show` statements.
///
/// Both characters are skins of the shared chibi-stickers skeleton: a Ren'Py
/// image such as `Image("erikari-emotes/angry.spine")` selects the `erikari`
/// skin and the `emotes/angry` animation.
const kSpineCharacters = [
  SpineCharacter(
    tag: 'erikari',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'erikari',
    idleAnimation: 'movement/idle-front',
  ),
  SpineCharacter(
    tag: 'harri',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'harri',
    idleAnimation: 'movement/idle-front',
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSpineFlutter(enableMemoryDebugging: false);
  runApp(const FiestaVNApp());
}

class FiestaVNApp extends StatelessWidget {
  const FiestaVNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenSpine - FiestaVN Demo',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const _LauncherScreen(),
    );
  }
}

/// Choose which game to play.
class _LauncherScreen extends StatelessWidget {
  const _LauncherScreen();

  // Convenience helper
  void _startGame(BuildContext ctx, String assetPath) {
    Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => GameScreen(assetPath: assetPath)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a demo game')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.looks_one),
              label: const Text('Reference Game 1'),
              onPressed:
                  () => _startGame(context, 'assets/games/1/game/script.rpy'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The game screen itself.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.assetPath});
  final String assetPath;

  /// Derives a title from the asset path. Prefers the segment after "games/"
  /// (e.g. "assets/games/1/game/script.rpy" -> "1"), otherwise falls back to
  /// the file name so unexpected layouts never throw.
  String get _title {
    final segments = assetPath.split('/').where((s) => s.isNotEmpty).toList();
    final gamesIdx = segments.indexOf('games');
    if (gamesIdx != -1 && gamesIdx + 1 < segments.length) {
      return segments[gamesIdx + 1];
    }
    return segments.isNotEmpty ? segments.last : assetPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: RenPyAssetPlayer(
        scriptAsset: assetPath,
        backgroundColor: Colors.grey.shade900,
        imageLayerBuilder: spineImageLayerBuilder(characters: kSpineCharacters),
      ),
    );
  }
}
