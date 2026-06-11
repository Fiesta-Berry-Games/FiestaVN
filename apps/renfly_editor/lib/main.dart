import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'src/editor_screen.dart';

void main() => runApp(const RenFlyEditorApp());

/// RenFly Editor: a web-first Ren'Py visual novel editor with live preview.
class RenFlyEditorApp extends StatelessWidget {
  const RenFlyEditorApp({
    super.key,
    this.audioPlayback,
    this.pickAssets,
    this.loadBundledAssets,
  });

  /// Overridable audio backend, primarily so widget tests can inject
  /// [RenPyNoOpAudioPlayback] and avoid platform audio plugins.
  final RenPyAudioPlayback? audioPlayback;

  /// Overridable asset picker for the Assets panel, so widget tests can
  /// inject in-memory files instead of a platform file dialog.
  final PickAssetFiles? pickAssets;

  /// Overridable startup loader for the bundled example art, so widget tests
  /// can inject in-memory bytes instead of real asset I/O.
  final LoadBundledAssets? loadBundledAssets;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF5A6E); // strawberry coral, matching fiestavn.com
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF121212),
    );
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'RenFly Editor',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF121212),
        canvasColor: const Color(0xFF121212),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(backgroundColor: accent),
        ),
      ),
      home: EditorScreen(
        audioPlayback: audioPlayback,
        pickAssets: pickAssets,
        loadBundledAssets: loadBundledAssets,
      ),
    );
  }
}
