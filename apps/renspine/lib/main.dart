import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:renpy_core/renpy_core.dart';
import 'package:renspine/widgets/spine_layer.dart';
import 'package:renspine/widgets/dialogue_view.dart';
import 'package:renspine/widgets/menu_selector.dart';
import 'package:spine_flutter/spine_flutter.dart' show initSpineFlutter;

import 'controller.dart';

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
    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => GameScreen(assetPath: assetPath)),
    );
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
              onPressed: () =>
                  _startGame(context, 'assets/games/1/game/script.rpy'),
            ),
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ctrl = RenPyFlutterController();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _source = await rootBundle.loadString(widget.assetPath);
    _ctrl.load(_source);
    if (mounted) setState(() => _loading = false);
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
          SpineLayer(controller: _ctrl),
          DialogueView(controller: _ctrl),
          MenuSelector(controller: _ctrl),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Restart',
        onPressed: () => _ctrl.load(_source), // quick reset
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
