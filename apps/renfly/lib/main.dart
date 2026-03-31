import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'project_picker.dart';

void main() => runApp(const FiestaVNApp());

class FiestaVNApp extends StatelessWidget {
  const FiestaVNApp({
    super.key,
    this.audioPlayback,
    this.projectPicker,
    this.onGameControllerCreated,
  });

  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectPicker? projectPicker;
  final ValueChanged<RenPyFlutterController>? onGameControllerCreated;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenFly - FiestaVN Demo',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: _LauncherScreen(
        audioPlayback: audioPlayback,
        projectPicker: projectPicker ?? createRenPyProjectPicker(),
        onGameControllerCreated: onGameControllerCreated,
      ),
    );
  }
}

/// Choose which game to play.
class _LauncherScreen extends StatelessWidget {
  const _LauncherScreen({
    this.audioPlayback,
    required this.projectPicker,
    this.onGameControllerCreated,
  });

  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectPicker projectPicker;
  final ValueChanged<RenPyFlutterController>? onGameControllerCreated;

  // Convenience helper
  void _startGame(BuildContext ctx, String title, String assetPath) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder:
            (_) => GameScreen(
              title: title,
              assetPath: assetPath,
              audioPlayback: audioPlayback,
              onControllerCreated: onGameControllerCreated,
            ),
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
                onControllerCreated: onGameControllerCreated,
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
                key: ValueKey('demo_game_${game.$1}'),
                icon: Icon(game.$3),
                label: Text(game.$1),
                onPressed: () => _startGame(context, game.$1, game.$2),
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
    this.onControllerCreated,
  });

  final RenPyGameProject project;
  final RenPyAudioPlayback? audioPlayback;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: _PersistentStoreLoader(
        storeKey: _persistentStoreKey(project.gameRoot),
        builder:
            (context, persistentStore) => RenPyProjectPlayer(
              project: project,
              backgroundColor: Colors.grey.shade900,
              audioPlayback: audioPlayback,
              onControllerCreated: onControllerCreated,
              persistentStore: persistentStore,
            ),
      ),
    );
  }
}

class _PersistentStoreLoader extends StatefulWidget {
  const _PersistentStoreLoader({required this.storeKey, required this.builder});

  final String storeKey;
  final Widget Function(BuildContext context, RenPyPersistentStore store)
  builder;

  @override
  State<_PersistentStoreLoader> createState() => _PersistentStoreLoaderState();
}

class _PersistentStoreLoaderState extends State<_PersistentStoreLoader> {
  late final Future<RenPyPersistentStore> _store =
      RenPySharedPreferencesPersistentStore.create(key: widget.storeKey);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RenPyPersistentStore>(
      future: _store,
      builder: (context, snapshot) {
        final store = snapshot.data;
        if (store != null) return widget.builder(context, store);

        final error = snapshot.error;
        if (error != null) {
          return Center(child: Text('Failed to load persistent data: $error'));
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

String _persistentStoreKey(String identifier) {
  return 'renfly.persistent.${Uri.encodeComponent(identifier)}';
}

/// The game screen itself.
class GameScreen extends StatelessWidget {
  const GameScreen({
    super.key,
    required this.title,
    required this.assetPath,
    this.audioPlayback,
    this.onControllerCreated,
  });

  final String title;
  final String assetPath;
  final RenPyAudioPlayback? audioPlayback;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _PersistentStoreLoader(
        storeKey: _persistentStoreKey(assetPath),
        builder:
            (context, persistentStore) => RenPyAssetPlayer(
              scriptAsset: assetPath,
              backgroundColor: Colors.grey.shade900,
              audioPlayback: audioPlayback,
              onControllerCreated: onControllerCreated,
              persistentStore: persistentStore,
            ),
      ),
    );
  }
}
