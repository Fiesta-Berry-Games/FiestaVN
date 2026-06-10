import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly_player/game_library.dart';
import 'package:renfly_player/main.dart';
import 'package:renfly_player/project_picker.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GameLibraryStore', () {
    test('persists added projects across a fresh store instance', () async {
      SharedPreferences.setMockInitialValues({});

      final store = await GameLibraryStore.create();
      expect(await store.load(), isEmpty);

      await store.add(
        const LibraryProject(
          id: '/games/demo',
          name: 'Demo',
          sourcePath: '/games/demo',
        ),
      );

      // A re-instantiated store reads the persisted entry.
      final reloaded = await GameLibraryStore.create();
      final projects = await reloaded.load();
      expect(projects, hasLength(1));
      expect(projects.single.id, '/games/demo');
      expect(projects.single.name, 'Demo');
      expect(projects.single.sourcePath, '/games/demo');
    });

    test('persists removal across a fresh store instance', () async {
      SharedPreferences.setMockInitialValues({});

      final store = await GameLibraryStore.create();
      await store.add(
        const LibraryProject(id: 'a', name: 'A', sourcePath: '/a'),
      );
      await store.add(
        const LibraryProject(id: 'b', name: 'B', sourcePath: '/b'),
      );

      await store.remove('a');

      final reloaded = await GameLibraryStore.create();
      final projects = await reloaded.load();
      expect(projects, hasLength(1));
      expect(projects.single.id, 'b');
    });

    test('markPlayed records a last-played timestamp', () async {
      SharedPreferences.setMockInitialValues({});

      final store = await GameLibraryStore.create();
      await store.add(
        const LibraryProject(id: 'a', name: 'A', sourcePath: '/a'),
      );

      final when = DateTime(2026, 5, 28, 9, 30);
      await store.markPlayed('a', when: when);

      final reloaded = await GameLibraryStore.create();
      final project = (await reloaded.load()).single;
      expect(project.lastPlayed, when);
    });
  });

  group('GameLibraryScreen', () {
    testWidgets('lists bundled games and persisted projects', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await GameLibraryStore.create();
      await store.add(
        const LibraryProject(
          id: '/games/saved',
          name: 'Saved Project',
          sourcePath: '/games/saved',
        ),
      );

      await _pumpLibrary(tester, store: store, picker: _FakeProjectPicker());

      expect(find.text('Choose a demo game'), findsOneWidget);
      expect(find.text('The Question'), findsOneWidget);
      expect(find.text('Saved Project'), findsOneWidget);
    });

    testWidgets('adding a project persists it and re-renders after reload', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = await GameLibraryStore.create();
      final picker = _FakeProjectPicker(
        sourcePath: '/games/added',
        project: _project('added'),
      );

      await _pumpLibrary(tester, store: store, picker: picker);
      expect(find.text('No external projects added yet.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library_add_project')));
      await _pumpUntil(tester, find.byType(ExternalGameScreen));

      // Adding launches the project directly into the player.
      expect(find.byType(ExternalGameScreen), findsOneWidget);

      // The added project survives a fresh library load from storage.
      final reloaded = await GameLibraryStore.create();
      final projects = await reloaded.load();
      expect(projects, hasLength(1));
      expect(projects.single.sourcePath, '/games/added');
    });

    testWidgets('removing a project persists removal', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await GameLibraryStore.create();
      await store.add(
        const LibraryProject(
          id: '/games/saved',
          name: 'Saved Project',
          sourcePath: '/games/saved',
        ),
      );

      await _pumpLibrary(tester, store: store, picker: _FakeProjectPicker());
      expect(find.text('Saved Project'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('library_remove_/games/saved')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved Project'), findsNothing);

      final reloaded = await GameLibraryStore.create();
      expect(await reloaded.load(), isEmpty);
    });

    testWidgets('launching a library entry opens the player for it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = await GameLibraryStore.create();
      await store.add(
        const LibraryProject(
          id: '/games/saved',
          name: 'Saved Project',
          sourcePath: '/games/saved',
        ),
      );
      final picker = _FakeProjectPicker(project: _project('Saved Project'));

      await _pumpLibrary(tester, store: store, picker: picker);

      await tester.tap(
        find.byKey(const ValueKey('library_project_/games/saved')),
      );
      await _pumpUntil(tester, find.byType(ExternalGameScreen));

      expect(picker.reloadedPaths, ['/games/saved']);
      expect(find.byType(ExternalGameScreen), findsOneWidget);

      // The launch was recorded as recently played.
      final played = (await GameLibraryStore.create()).load();
      expect((await played).single.lastPlayed, isNotNull);
    });
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required GameLibraryStore store,
  required RenPyProjectPicker picker,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    FiestaVNApp(key: UniqueKey(), projectPicker: picker, libraryStore: store),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int attempts = 80,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder.');
}

RenPyGameProject _project(String name) {
  return RenPyGameProject.fromFiles([
    RenPyProjectFile.text('$name/game/script.rpy', '''
label start:
    "Hello from $name."
'''),
  ]);
}

final class _FakeProjectPicker implements RenPyProjectPicker {
  _FakeProjectPicker({this.sourcePath, RenPyGameProject? project})
    : project = project ?? _project('Fake');

  final String? sourcePath;
  final RenPyGameProject project;
  final List<String> reloadedPaths = [];

  @override
  Future<PickedProject?> pickProject() async {
    return PickedProject(project, sourcePath: sourcePath);
  }

  @override
  Future<PickedProject?> pickFile() async {
    return PickedProject(project, sourcePath: sourcePath);
  }

  @override
  Future<RenPyGameProject?> reloadProject(String path) async {
    reloadedPaths.add(path);
    return project;
  }
}
