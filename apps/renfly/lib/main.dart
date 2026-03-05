import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:renpy_flutter/renpy_flutter.dart';

void main() => runApp(const FiestaVNApp());

class FiestaVNApp extends StatelessWidget {
  const FiestaVNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenFly - FiestaVN Demo',
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
    const games = [
      ('Reference Game 1', 'assets/games/1/game/script.rpy', Icons.looks_one),
      ('Reference Game 2', 'assets/games/2/game/script.rpy', Icons.looks_two),
      ('Reference Game 3', 'assets/games/3/game/script.rpy', Icons.looks_3),
      (
        'The Question',
        'assets/games/the_question/game/script.rpy',
        Icons.question_answer,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a demo game')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final game in games) ...[
              ElevatedButton.icon(
                icon: Icon(game.$3),
                label: Text(game.$1),
                onPressed: () => _startGame(context, game.$2),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// The game screen itself.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.assetPath});
  final String assetPath;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final RenPyFlutterController _ctrl;
  late String _source;
  Set<String> _availableAssets = {};
  bool _loading = true;

  String get _gameRoot => widget.assetPath.substring(
    0,
    widget.assetPath.lastIndexOf('/script.rpy'),
  );

  @override
  void initState() {
    super.initState();
    _ctrl = RenPyFlutterController();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _source = await rootBundle.loadString(widget.assetPath);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    _availableAssets =
        manifest
            .listAssets()
            .where((asset) => asset.startsWith(_gameRoot))
            .toSet();

    // First draw the real game screen so that ImageLayer attaches its listener.
    if (!mounted) return;
    setState(() => _loading = false);

    // Run the script on the very next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ctrl.load(
          _source,
          filename: widget.assetPath,
          gameRoot: _gameRoot,
          availableAssets: _availableAssets,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.assetPath.split('/').elementAt(2))),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.grey.shade900),
          RenPyImageLayer(controller: _ctrl),
          RenPyDialogueView(controller: _ctrl),
          RenPyMenuSelector(controller: _ctrl),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Restart',
        onPressed:
            () => _ctrl.load(
              _source,
              filename: widget.assetPath,
              gameRoot: _gameRoot,
              availableAssets: _availableAssets,
            ),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
