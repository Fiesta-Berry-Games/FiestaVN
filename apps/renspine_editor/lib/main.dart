import 'package:flutter/material.dart';
import 'package:renfly_editor/renfly_editor.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_spine/renpy_spine.dart';

import 'src/spine_editor_config.dart';
import 'src/spine_gallery_section.dart';

export 'src/spine_editor_config.dart';
export 'src/spine_gallery_section.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Spine native runtime must be up before any sprite is built.
  await initSpineFlutter(enableMemoryDebugging: false);
  runApp(const RenSpineEditorApp());
}

/// RenSpine Editor: the RenFly editor IDE composed with the renpy_spine
/// bridge — a live preview that stages Spine-animated characters, a Spine
/// section in the Characters gallery, and a bundled two-character demo.
class RenSpineEditorApp extends StatelessWidget {
  const RenSpineEditorApp({
    super.key,
    this.audioPlayback,
    this.pickAssets,
    this.loadBundledAssets,
    this.imageLayerBuilder,
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

  /// Overridable preview image layer. Defaults to [spinePreviewImageLayer]
  /// (the renpy_spine routing layer); widget tests inject
  /// [spineSuppressingImageLayer] because Spine widgets need the
  /// spine_flutter native runtime, which headless tests cannot load.
  final EditorPreviewLayerBuilder? imageLayerBuilder;

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
      title: 'RenSpine Editor',
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
        title: 'RenSpine Editor',
        audioPlayback: audioPlayback,
        pickAssets: pickAssets,
        loadBundledAssets: loadBundledAssets,
        imageLayerBuilder: imageLayerBuilder ?? spinePreviewImageLayer,
        extraExamples: renSpineEditorExamples,
        initialExample: renSpineEditorExamples.first,
        extraPreviewAssets: spinePreviewAssets(),
        extraGallerySection:
            (context, insertStatements) => SpineGallerySection(
              characters: kSpineCharacters,
              animations: kSpineAnimations,
              onInsert: insertStatements,
            ),
      ),
    );
  }
}
