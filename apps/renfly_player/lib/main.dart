import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'game_library.dart';
import 'project_picker.dart';
import 'streamed_game.dart';

void main() => runApp(const FiestaVNApp());

class FiestaVNApp extends StatelessWidget {
  const FiestaVNApp({
    super.key,
    this.audioPlayback,
    this.projectPicker,
    this.libraryStore,
    this.onGameControllerCreated,
  });

  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectPicker? projectPicker;
  final GameLibraryStore? libraryStore;
  final ValueChanged<RenPyFlutterController>? onGameControllerCreated;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenFly Player',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: GameLibraryScreen(
        audioPlayback: audioPlayback,
        projectPicker: projectPicker ?? createRenPyProjectPicker(),
        libraryStore: libraryStore,
        onGameControllerCreated: onGameControllerCreated,
      ),
    );
  }
}

/// A bundled reference game shipped as Flutter assets. Always present and not
/// removable.
final class _BundledGame {
  const _BundledGame(this.title, this.assetPath, this.icon);

  final String title;
  final String assetPath;
  final IconData icon;
}

const List<_BundledGame> _bundledGames = [
  _BundledGame(
    'The Question',
    'assets/games/the_question/game/script.rpy',
    Icons.question_answer,
  ),
];

/// Lists the bundled reference games and any user-added external projects,
/// letting the player add, remove, and launch projects.
class GameLibraryScreen extends StatefulWidget {
  const GameLibraryScreen({
    super.key,
    this.audioPlayback,
    required this.projectPicker,
    this.libraryStore,
    this.onGameControllerCreated,
  });

  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectPicker projectPicker;
  final GameLibraryStore? libraryStore;
  final ValueChanged<RenPyFlutterController>? onGameControllerCreated;

  @override
  State<GameLibraryScreen> createState() => _GameLibraryScreenState();
}

class _GameLibraryScreenState extends State<GameLibraryScreen> {
  GameLibraryStore? _store;
  List<LibraryProject> _projects = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
    // `/play/?stream=<url>` deep-links straight into a streamed game; the
    // URL may be origin-relative (e.g. `/games/the-question/`).
    if (kIsWeb) {
      final stream = Uri.base.queryParameters['stream'];
      if (stream != null && stream.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startStreamedGame(Uri.base.resolve(stream).toString());
        });
      }
    }
  }

  void _startStreamedGame(String baseUrl, {String? title}) {
    Navigator.of(context).push(
      _renPyGameRoute(
        builder:
            (_) => StreamedGameScreen(
              baseUrl: baseUrl,
              title: title,
              audioPlayback: widget.audioPlayback,
              onControllerCreated: widget.onGameControllerCreated,
            ),
      ),
    );
  }

  Future<void> _initialize() async {
    final store = widget.libraryStore ?? await GameLibraryStore.create();
    final projects = await store.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _projects = _sortedByRecent(projects);
      _loading = false;
    });
  }

  static List<LibraryProject> _sortedByRecent(List<LibraryProject> projects) {
    final sorted = [...projects];
    sorted.sort((a, b) {
      final aTime = a.lastPlayed;
      final bTime = b.lastPlayed;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  void _startBundledGame(BuildContext ctx, _BundledGame game) {
    Navigator.of(ctx).push(
      _renPyGameRoute(
        builder:
            (_) => GameScreen(
              title: game.title,
              assetPath: game.assetPath,
              audioPlayback: widget.audioPlayback,
              onControllerCreated: widget.onGameControllerCreated,
            ),
      ),
    );
  }

  Future<void> _addProject() async {
    final store = _store;
    if (store == null) return;
    try {
      final picked = await widget.projectPicker.pickProject();
      if (picked == null || !mounted) return;

      final project = picked.project;
      final entry = LibraryProject(
        id: picked.sourcePath ?? project.gameRoot,
        name: project.name,
        sourcePath: picked.sourcePath,
      );
      final projects = await store.add(entry);
      if (!mounted) return;
      setState(() => _projects = _sortedByRecent(projects));

      // The freshly picked project is already loaded; launch it directly so
      // web uploads (which cannot be reloaded) play immediately.
      _launchExternalProject(entry, project);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open folder: $error')));
    }
  }

  Future<void> _addFile() async {
    final store = _store;
    if (store == null) return;
    try {
      final picked = await widget.projectPicker.pickFile();
      if (picked == null || !mounted) return;

      final project = picked.project;
      final entry = LibraryProject(
        id: picked.sourcePath ?? project.gameRoot,
        name: project.name,
        sourcePath: picked.sourcePath,
      );
      final projects = await store.add(entry);
      if (!mounted) return;
      setState(() => _projects = _sortedByRecent(projects));
      _launchExternalProject(entry, project);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open file: $error')));
    }
  }

  Future<void> _removeProject(LibraryProject project) async {
    final store = _store;
    if (store == null) return;
    final projects = await store.remove(project.id);
    if (!mounted) return;
    setState(() => _projects = _sortedByRecent(projects));
  }

  Future<void> _launchLibraryProject(LibraryProject entry) async {
    final store = _store;
    if (store == null) return;

    RenPyGameProject? project;
    if (entry.canReload) {
      try {
        project = await widget.projectPicker.reloadProject(entry.sourcePath!);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reload project: $error')),
        );
        return;
      }
    }

    if (!mounted) return;
    if (project == null) {
      // No durable source (web upload) or the folder is gone; ask the player
      // to re-pick the project.
      final picked = await widget.projectPicker.pickProject();
      if (picked == null || !mounted) return;
      project = picked.project;
    }

    final played = await store.markPlayed(entry.id);
    if (!mounted) return;
    setState(() => _projects = _sortedByRecent(played));
    _launchExternalProject(entry, project);
  }

  void _launchExternalProject(LibraryProject entry, RenPyGameProject project) {
    Navigator.of(context).push(
      _renPyGameRoute(
        builder:
            (_) => ExternalGameScreen(
              storeIdentifier: entry.id,
              project: project,
              audioPlayback: widget.audioPlayback,
              onControllerCreated: widget.onGameControllerCreated,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a demo game'),
        actions: [
          IconButton(
            key: const ValueKey('library_add_project'),
            icon: const Icon(Icons.add),
            tooltip: 'Add project',
            onPressed: _loading ? null : _addProject,
          ),
          // The renfly.org embed overlays an "Open fullscreen" button on the
          // top-right corner of the iframe; keep our actions clear of it.
          if (kIsWeb) const SizedBox(width: 48),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  const _LibrarySectionHeader('Demo games'),
                  for (final game in _bundledGames)
                    ListTile(
                      key: ValueKey('demo_game_${game.title}'),
                      leading: Icon(game.icon),
                      title: Text(game.title),
                      trailing: const Icon(Icons.play_arrow),
                      onTap: () => _startBundledGame(context, game),
                    ),
                  // Streamed demos only resolve against the hosting site's
                  // origin, so they're web-only.
                  if (kIsWeb)
                    ListTile(
                      key: const ValueKey('demo_game_streamed_the_question'),
                      leading: const Icon(Icons.cloud_download),
                      title: const Text('The Question (.fly, streamed)'),
                      subtitle: const Text(
                        'Assets stream as the story needs them · '
                        'starts at the first scene',
                      ),
                      trailing: const Icon(Icons.play_arrow),
                      onTap:
                          () => _startStreamedGame(
                            Uri.base.resolve('/games/the-question/').toString(),
                            title: 'The Question',
                          ),
                    ),
                  const _LibrarySectionHeader('Your projects'),
                  if (_projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text('No external projects added yet.'),
                    ),
                  for (final project in _projects)
                    ListTile(
                      key: ValueKey('library_project_${project.id}'),
                      leading: const Icon(Icons.videogame_asset),
                      title: Text(project.name),
                      subtitle: _subtitleFor(project),
                      trailing: IconButton(
                        key: ValueKey('library_remove_${project.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove from library',
                        onPressed: () => _removeProject(project),
                      ),
                      onTap: () => _launchLibraryProject(project),
                    ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Open Folder'),
                    subtitle: const Text('Classic Ren\'Py project directory'),
                    onTap: _addProject,
                  ),
                  ListTile(
                    leading: const Icon(Icons.file_open),
                    title: const Text('Open File'),
                    subtitle: const Text('.fly, .fly.zip, or .rpy'),
                    onTap: _addFile,
                  ),
                ],
              ),
    );
  }

  Widget? _subtitleFor(LibraryProject project) {
    final parts = <String>[];
    if (!project.canReload) parts.add('Re-pick required');
    final lastPlayed = project.lastPlayed;
    if (lastPlayed != null) {
      parts.add('Last played ${_formatTimestamp(lastPlayed)}');
    }
    if (parts.isEmpty) return null;
    return Text(parts.join(' - '));
  }
}

String _formatTimestamp(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

PageRoute<T> _renPyGameRoute<T>({required WidgetBuilder builder}) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

class ExternalGameScreen extends StatelessWidget {
  const ExternalGameScreen({
    super.key,
    required this.project,
    this.storeIdentifier,
    this.audioPlayback,
    this.onControllerCreated,
  });

  final RenPyGameProject project;

  /// Stable key for this project's save-slot stores. Defaults to the project's
  /// game root, but the library passes the persisted entry id so saves stay
  /// associated with the right game even when the game root is empty.
  final String? storeIdentifier;
  final RenPyAudioPlayback? audioPlayback;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;

  @override
  Widget build(BuildContext context) {
    final identifier =
        (storeIdentifier != null && storeIdentifier!.isNotEmpty)
            ? storeIdentifier!
            : project.gameRoot;
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: _PersistentStoreLoader(
        identifier: identifier,
        builder:
            (context, stores) => RenPyProjectPlayer(
              project: project,
              backgroundColor: Colors.grey.shade900,
              audioPlayback: audioPlayback,
              onControllerCreated: onControllerCreated,
              persistentStore: stores.persistent,
              snapshotStore: stores.snapshot,
              slotStore: stores.slots,
              preferenceStore: stores.preferences,
            ),
      ),
    );
  }
}

class _PersistentStoreLoader extends StatefulWidget {
  const _PersistentStoreLoader({
    required this.identifier,
    required this.builder,
  });

  final String identifier;
  final Widget Function(BuildContext context, _GameStores stores) builder;

  @override
  State<_PersistentStoreLoader> createState() => _PersistentStoreLoaderState();
}

final class _GameStores {
  const _GameStores({
    required this.persistent,
    required this.snapshot,
    required this.slots,
    required this.preferences,
  });

  final RenPyPersistentStore persistent;
  final RenPyRunnerSnapshotStore snapshot;
  final RenPyRunnerSnapshotSlotStore slots;
  final RenPyPreferenceStore preferences;
}

class _PersistentStoreLoaderState extends State<_PersistentStoreLoader> {
  late final Future<_GameStores> _stores = _loadStores();

  Future<_GameStores> _loadStores() async {
    final persistentStore = await RenPySharedPreferencesPersistentStore.create(
      key: _persistentStoreKey(widget.identifier),
    );
    final snapshotStore = await RenPySharedPreferencesSnapshotStore.create(
      key: _snapshotStoreKey(widget.identifier),
    );
    final slotStore = await RenPySharedPreferencesSnapshotSlotStore.create(
      keyPrefix: _slotStoreKeyPrefix(widget.identifier),
    );
    final preferenceStore = await RenPySharedPreferencesPreferenceStore.create(
      key: _preferenceStoreKey(widget.identifier),
    );
    return _GameStores(
      persistent: persistentStore,
      snapshot: snapshotStore,
      slots: slotStore,
      preferences: preferenceStore,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GameStores>(
      future: _stores,
      builder: (context, snapshot) {
        final stores = snapshot.data;
        if (stores != null) return widget.builder(context, stores);

        final error = snapshot.error;
        if (error != null) {
          return Center(child: Text('Failed to load game data: $error'));
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

String _persistentStoreKey(String identifier) {
  return 'renfly.persistent.${Uri.encodeComponent(identifier)}';
}

String _snapshotStoreKey(String identifier) {
  return 'renfly.snapshot.${Uri.encodeComponent(identifier)}';
}

String _slotStoreKeyPrefix(String identifier) {
  return 'renfly.slot.${Uri.encodeComponent(identifier)}';
}

String _preferenceStoreKey(String identifier) {
  return 'renfly.preferences.${Uri.encodeComponent(identifier)}';
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
        identifier: assetPath,
        builder:
            (context, stores) => RenPyAssetPlayer(
              scriptAsset: assetPath,
              backgroundColor: Colors.grey.shade900,
              audioPlayback: audioPlayback,
              onControllerCreated: onControllerCreated,
              persistentStore: stores.persistent,
              snapshotStore: stores.snapshot,
              slotStore: stores.slots,
              preferenceStore: stores.preferences,
            ),
      ),
    );
  }
}
