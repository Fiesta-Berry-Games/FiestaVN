import 'package:flutter/material.dart';
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
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.assetPath});
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(assetPath.split('/').elementAt(2))),
      body: RenPyAssetPlayer(
        scriptAsset: assetPath,
        backgroundColor: Colors.grey.shade900,
      ),
    );
  }
}
