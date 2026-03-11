import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'project_picker.dart';

void main() => runApp(const FiestaVNApp());

class FiestaVNApp extends StatelessWidget {
  const FiestaVNApp({super.key, this.audioPlayback, this.projectPicker});

  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectPicker? projectPicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenFly - FiestaVN Demo',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: _LauncherScreen(
        audioPlayback: audioPlayback,
        projectPicker: projectPicker ?? createRenPyProjectPicker(),
      ),
    );
  }
}

/// Choose which game to play.
class _LauncherScreen extends StatelessWidget {
  const _LauncherScreen({this.audioPlayback, required this.projectPicker});

  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectPicker projectPicker;

  // Convenience helper
  void _startGame(BuildContext ctx, String assetPath) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder:
            (_) =>
                GameScreen(assetPath: assetPath, audioPlayback: audioPlayback),
      ),
    );
  }

  Future<void> _openProject(BuildContext context) async {
    try {
      final project = await projectPicker.pickProject();
      if (project == null || !context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ExternalGameScreen(
                project: project,
                audioPlayback: audioPlayback,
              ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open folder: $error')));
    }
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
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Folder'),
              onPressed: () => _openProject(context),
            ),
          ],
        ),
      ),
    );
  }
}

class ExternalGameScreen extends StatelessWidget {
  const ExternalGameScreen({
    super.key,
    required this.project,
    this.audioPlayback,
  });

  final RenPyGameProject project;
  final RenPyAudioPlayback? audioPlayback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: RenPyProjectPlayer(
        project: project,
        backgroundColor: Colors.grey.shade900,
        audioPlayback: audioPlayback,
      ),
    );
  }
}

/// The game screen itself.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.assetPath, this.audioPlayback});

  final String assetPath;
  final RenPyAudioPlayback? audioPlayback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(assetPath.split('/').elementAt(2))),
      body: RenPyAssetPlayer(
        scriptAsset: assetPath,
        backgroundColor: Colors.grey.shade900,
        audioPlayback: audioPlayback,
      ),
    );
  }
}
