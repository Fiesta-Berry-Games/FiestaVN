import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_spine/renpy_spine.dart';

import 'spine_preloader.dart';

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
  SpineCharacter(
    tag: 'misaki',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'misaki',
    idleAnimation: 'movement/idle-front',
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSpineFlutter(enableMemoryDebugging: false);
  runApp(const FiestaVNApp());
}

/// Builds the screen pushed when a game launches. Tests inject a stub so
/// navigation can be asserted without booting the full Ren'Py player.
typedef GameScreenBuilder = Widget Function(String assetPath, String title);

class FiestaVNApp extends StatelessWidget {
  const FiestaVNApp({super.key, this.loadAsset, this.gameScreenBuilder});

  /// Seam for the Spine asset preloader; defaults to `rootBundle.load`.
  @visibleForTesting
  final AssetLoader? loadAsset;

  /// Seam for the pushed game screen; defaults to [GameScreen].
  @visibleForTesting
  final GameScreenBuilder? gameScreenBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenSpine - FiestaVN Demo',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: _LauncherScreen(
        loadAsset: loadAsset,
        gameScreenBuilder: gameScreenBuilder,
      ),
    );
  }
}

/// Choose which game to play.
///
/// Before pushing a game it preloads the Spine assets the game's characters
/// need (on web those are network fetches), showing a determinate per-file
/// progress bar on the launcher tile. The success bit is remembered by the
/// preloader, so a second launch navigates immediately.
class _LauncherScreen extends StatefulWidget {
  const _LauncherScreen({this.loadAsset, this.gameScreenBuilder});

  final AssetLoader? loadAsset;
  final GameScreenBuilder? gameScreenBuilder;

  @override
  State<_LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<_LauncherScreen> {
  late final SpineAssetPreloader _preloader = SpineAssetPreloader(
    characters: kSpineCharacters,
    loadAsset: widget.loadAsset,
  );

  @override
  void dispose() {
    _preloader.dispose();
    super.dispose();
  }

  Future<void> _startGame(String assetPath, String title) async {
    if (!_preloader.isLoaded) {
      try {
        await _preloader.ensureLoaded();
      } catch (_) {
        // The preloader records the error; the tile shows a retry button.
        return;
      }
      if (!mounted) return;
    }
    final buildGame =
        widget.gameScreenBuilder ??
        (path, gameTitle) => GameScreen(assetPath: path, title: gameTitle);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => buildGame(assetPath, title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a demo game')),
      body: Center(
        child: ListenableBuilder(
          listenable: _preloader,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('fiesta-skit-tile'),
                  icon: const Icon(Icons.celebration),
                  label: const Text('Fiesta Skit - Spine Showcase'),
                  onPressed:
                      _preloader.isLoading
                          ? null
                          : () => _startGame(
                            'assets/games/1/game/script.rpy',
                            'Fiesta Skit',
                          ),
                ),
                if (_preloader.isLoading) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 240,
                    child: LinearProgressIndicator(
                      key: const ValueKey('spine-preload-progress'),
                      value: _preloader.progress,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loading characters… '
                    '${_preloader.loadedCount}/${_preloader.totalCount}',
                    key: const ValueKey('spine-preload-progress-label'),
                  ),
                ] else if (_preloader.error != null) ...[
                  const SizedBox(height: 16),
                  const Text('Could not load the characters.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('spine-preload-retry'),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed:
                        () => _startGame(
                          'assets/games/1/game/script.rpy',
                          'Fiesta Skit',
                        ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The game screen itself.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.assetPath, this.title});
  final String assetPath;

  /// Display title for the app bar; falls back to a path-derived name.
  final String? title;

  /// Derives a title from the asset path. Prefers the explicit [title], then
  /// the segment after "games/" (e.g. "assets/games/1/game/script.rpy" ->
  /// "1"), otherwise falls back to the file name so unexpected layouts never
  /// throw.
  String get _title {
    final explicit = title;
    if (explicit != null && explicit.isNotEmpty) return explicit;
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
