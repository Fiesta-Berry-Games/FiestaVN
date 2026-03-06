import 'package:flutter/material.dart';
import 'package:renspine/widgets/spine_layer.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:spine_flutter/spine_flutter.dart' show initSpineFlutter;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(assetPath.split('/').elementAt(2))),
      body: RenPyAssetPlayer(
        scriptAsset: assetPath,
        backgroundColor: Colors.grey.shade900,
        imageLayerBuilder:
            (context, controller) => SpineLayer(controller: controller),
      ),
    );
  }
}
