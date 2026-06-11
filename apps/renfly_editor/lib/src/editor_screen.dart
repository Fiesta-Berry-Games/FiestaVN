import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/renpy_writer.dart';

import 'file_saver.dart';
import 'migration_report.dart';
import 'starter_template.dart';
import 'syntax_highlight.dart';

/// How long typing is left to settle before the script is re-parsed for
/// diagnostics.
const Duration parseDebounce = Duration(milliseconds: 400);

/// Below this width the editor and preview stack vertically behind tabs.
const double _narrowBreakpoint = 700;

/// One picked asset file: the picker-reported file name plus content bytes.
typedef PickedAssetFile = ({String name, Uint8List bytes});

/// Signature of the file picker behind the Assets panel's "Add…" button.
///
/// Returns null when the user cancels. Tests inject a fake that returns
/// in-memory bytes so no platform file dialog is involved.
typedef PickAssetFiles = Future<List<PickedAssetFile>?> Function();

/// Where an added file lands in the session, by extension: images under
/// `game/images/`, audio under `game/audio/`, everything else under `game/`.
String sessionAssetPathFor(String filename) {
  final base = filename.replaceAll(r'\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final extension = dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
  if (const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(extension)) {
    return 'game/images/$base';
  }
  if (const {'ogg', 'opus', 'mp3', 'wav'}.contains(extension)) {
    return 'game/audio/$base';
  }
  return 'game/$base';
}

/// Where The Question's bundled art lives in the Flutter asset bundle.
const String _bundledArtRoot = 'assets/examples/the_question';

/// The Question's art files, as session asset paths relative to
/// [_bundledArtRoot]. They are copies of apps/renfly_player's reference-game
/// assets: four backgrounds, eight Sylvie sprites, and the music track.
const List<String> bundledExampleAssetFiles = [
  'game/images/bg club.jpg',
  'game/images/bg lecturehall.jpg',
  'game/images/bg meadow.jpg',
  'game/images/bg uni.jpg',
  'game/images/sylvie blue giggle.png',
  'game/images/sylvie blue normal.png',
  'game/images/sylvie blue smile.png',
  'game/images/sylvie blue surprised.png',
  'game/images/sylvie green giggle.png',
  'game/images/sylvie green normal.png',
  'game/images/sylvie green smile.png',
  'game/images/sylvie green surprised.png',
  'game/illurock.opus',
];

/// Signature of the startup loader that fills the session's asset map with
/// the bundled example art, keyed by session path (`game/images/...`,
/// `game/illurock.opus`). Tests inject in-memory bytes so no real asset I/O
/// runs inside the fake-async test zone.
typedef LoadBundledAssets = Future<Map<String, Uint8List>> Function();

/// Loads one of the editor's own bundled assets as a string, whether the
/// editor runs standalone (plain asset key) or composed inside a host app
/// (where renfly_editor's assets live under the `packages/renfly_editor/`
/// prefix).
Future<String> loadEditorAssetString(String path) async {
  if (_editorAssetsArePackaged == true) {
    return rootBundle.loadString('packages/renfly_editor/$path');
  }
  try {
    final text = await rootBundle.loadString(path);
    _editorAssetsArePackaged = false;
    return text;
  } catch (_) {
    final text = await rootBundle.loadString('packages/renfly_editor/$path');
    _editorAssetsArePackaged = true;
    return text;
  }
}

/// Whether the editor's own assets live under the `packages/renfly_editor/`
/// prefix (true when composed inside a host app). Learned on the first
/// successful load so later loads skip the 404-producing wrong attempt.
bool? _editorAssetsArePackaged;

/// Byte-loading counterpart of [loadEditorAssetString].
Future<ByteData> _loadEditorAssetBytes(String path) async {
  if (_editorAssetsArePackaged == true) {
    return rootBundle.load('packages/renfly_editor/$path');
  }
  try {
    final data = await rootBundle.load(path);
    _editorAssetsArePackaged = false;
    return data;
  } catch (_) {
    final data = await rootBundle.load('packages/renfly_editor/$path');
    _editorAssetsArePackaged = true;
    return data;
  }
}

/// Default [LoadBundledAssets]: reads The Question's art out of the Flutter
/// asset bundle so every preview can `scene bg lecturehall` and
/// `show sylvie green smile` with real art out of the box.
Future<Map<String, Uint8List>> loadBundledExampleAssets() async {
  final loaded = <String, Uint8List>{};
  for (final path in bundledExampleAssetFiles) {
    final data = await _loadEditorAssetBytes('$_bundledArtRoot/$path');
    loaded[path] = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
  }
  return loaded;
}

/// A bundled example story selectable from the "Examples ▾" menu.
class EditorExample {
  const EditorExample(this.id, this.label, this.load);

  /// Stable id used in widget keys (`editor-example-<id>`).
  final String id;

  /// Menu label.
  final String label;

  /// Produces the example's `.rpy` source text.
  final Future<String> Function() load;
}

/// The built-in examples, in menu order. The starter template stays first;
/// The Question is the Ren'Py reference game's script, and Sylvie & Sylvie
/// stages two sprites at once — both preview with the bundled art that
/// [loadBundledExampleAssets] seeds into the session at startup.
final List<EditorExample> editorExamples = [
  EditorExample('starter', 'Starter story', () async => starterTemplate),
  EditorExample(
    'the-question',
    "The Question (Ren'Py reference)",
    () => loadEditorAssetString('assets/examples/the_question.rpy'),
  ),
  EditorExample(
    'sylvie-and-sylvie',
    'Sylvie & Sylvie (two-character demo)',
    () => loadEditorAssetString('assets/examples/sylvie_and_sylvie.rpy'),
  ),
];

/// One image asset in the character gallery, named by the filename
/// convention `<tag> <variant...>.<ext>` under `game/images/` (e.g. tag
/// `sylvie`, variant `green smile`).
class GalleryImage {
  const GalleryImage(this.tag, this.variant, this.path);

  /// The first word of the filename — a sprite tag like `sylvie`, or `bg`.
  final String tag;

  /// The remaining words joined by spaces (may be empty).
  final String variant;

  /// The session asset path, e.g. `game/images/sylvie green smile.png`.
  final String path;

  /// The name `show`/`scene` statements use, e.g. `sylvie green smile`.
  String get showName => variant.isEmpty ? tag : '$tag $variant';
}

/// Groups session image assets for the character gallery: direct children of
/// `game/images/` split into characters keyed by tag, with the `bg` tag
/// pulled out as backgrounds. Non-image paths are ignored. Lists come back
/// sorted by path so the gallery order is stable.
({Map<String, List<GalleryImage>> characters, List<GalleryImage> backgrounds})
groupGalleryImages(Iterable<String> assetPaths) {
  const prefix = 'game/images/';
  final characters = <String, List<GalleryImage>>{};
  final backgrounds = <GalleryImage>[];
  final sorted = assetPaths.toList()..sort();
  for (final path in sorted) {
    if (!path.startsWith(prefix)) continue;
    final base = path.substring(prefix.length);
    if (base.contains('/')) continue;
    final dot = base.lastIndexOf('.');
    final extension = dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
    if (!const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(extension)) {
      continue;
    }
    final words =
        base.substring(0, dot).split(' ')..removeWhere((word) => word.isEmpty);
    if (words.isEmpty) continue;
    final image = GalleryImage(words.first, words.skip(1).join(' '), path);
    if (image.tag == 'bg') {
      backgrounds.add(image);
    } else {
      characters.putIfAbsent(image.tag, () => []).add(image);
    }
  }
  return (characters: characters, backgrounds: backgrounds);
}

/// Builds the preview player's image layer, replacing the editor's default
/// [RenPyImageLayer]. The editor hands over its live [controller], the
/// [screenSize] parsed from the current script (or the fallback), and its
/// session-asset-aware [imageProvider], so hosts can compose their own layer
/// (e.g. a Spine overlay) without re-implementing asset resolution.
typedef EditorPreviewLayerBuilder =
    Widget Function(
      BuildContext context,
      RenPyFlutterController controller,
      RenPyScreenSize screenSize,
      ImageProvider<Object> Function(String assetPath) imageProvider,
    );

/// Builds an extra section appended to the Characters gallery dialog.
/// [insertStatements] closes the dialog and inserts the given script lines at
/// the editor cursor (indented to the surrounding block), exactly like the
/// built-in gallery tiles do.
typedef GallerySectionBuilder =
    Widget Function(
      BuildContext context,
      void Function(List<String> statements) insertStatements,
    );

enum _IssueSeverity { error, warning }

final class _Issue {
  const _Issue(this.severity, this.message);

  final _IssueSeverity severity;
  final String message;
}

/// The single-screen IDE: toolbar, script editor, and live preview.
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.audioPlayback,
    this.pickAssets,
    this.loadBundledAssets,
    this.title = 'RenFly Editor',
    this.imageLayerBuilder,
    this.extraExamples = const [],
    this.extraGallerySection,
    this.extraPreviewAssets = const {},
  });

  /// Optional audio backend override for the preview player (tests inject
  /// [RenPyNoOpAudioPlayback]).
  final RenPyAudioPlayback? audioPlayback;

  /// Optional file-picker override for the Assets panel's "Add…" button
  /// (tests inject in-memory bytes). Defaults to `FilePicker.pickFiles`.
  final PickAssetFiles? pickAssets;

  /// Optional override for the startup load of the bundled example art
  /// (tests inject in-memory bytes). Defaults to [loadBundledExampleAssets].
  final LoadBundledAssets? loadBundledAssets;

  /// The toolbar title. Host apps composing this screen can rebrand it
  /// (e.g. 'RenSpine Editor').
  final String title;

  /// Optional preview image-layer override. When null the editor renders the
  /// default [RenPyImageLayer] resolved against the session assets.
  final EditorPreviewLayerBuilder? imageLayerBuilder;

  /// Extra examples appended after [editorExamples] in the "Examples ▾" menu.
  final List<EditorExample> extraExamples;

  /// Optional extra section appended to the Characters gallery dialog (e.g. a
  /// host's "Spine characters" section with its own tiles and insertions).
  final GallerySectionBuilder? extraGallerySection;

  /// Virtual asset paths merged into the preview's `availableAssets` on every
  /// load, alongside the session assets. Hosts whose image layer resolves
  /// paths outside the session byte map (e.g. `game/erikari-emotes/wave.spine`
  /// rendered by a Spine runtime) list them here so the player does not flag
  /// them as unresolved.
  final Set<String> extraPreviewAssets;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _scriptController;
  late final ScrollController _editorScrollController;
  late final RenPyFlutterController _previewController;

  /// Memory-only stores so editor preview runs never pollute persisted saves.
  /// The stage defaults to letterbox (fit): the preview pane is often
  /// near-square, where the player's auto fill mode would crop off the
  /// stage's left/right edges — hiding characters shown `at left`/`at right`.
  /// Authors need to see the whole stage.
  final RenPyMemoryPreferenceStore _preferenceStore =
      RenPyMemoryPreferenceStore({
        RenPyPlayerPreferences.stageFitKey: RenPyStageFit.fit.name,
      });

  /// Assets bundled with the opened script (from a `.fly.zip`), keyed by
  /// archive path (e.g. `game/images/bg.png`). The preview resolves images
  /// from here so characters and backgrounds actually display.
  final Map<String, Uint8List> _assets = {};

  /// The bundled example art, loaded once at startup and re-seeded into
  /// [_assets] whenever a new script replaces the session, so every preview
  /// has The Question's backgrounds and Sylvie sprites available.
  Map<String, Uint8List> _bundledAssets = const {};

  Timer? _debounce;
  Timer? _followDebounce;
  bool _dirty = false;
  bool _suppressDirty = false;
  bool _hasRun = false;
  double _splitRatio = 0.5;
  int _activeTab = 0; // 0 = editor, 1 = preview (narrow layout only).
  String _lastText = '';

  /// The cursor line the running preview was last brought to, so selection
  /// changes within the same line don't reload the preview.
  int _previewCursorLine = 0;

  /// True while the editor itself is (re)positioning the preview, so the
  /// resulting burst of runner events doesn't bounce back into the cursor.
  bool _syncingPreview = false;

  RenPyParseError? _parseError;
  List<String> _parseWarnings = const [];
  final List<String> _runDiagnostics = [];

  @override
  void initState() {
    super.initState();
    _editorScrollController = ScrollController();
    _lastText = starterTemplate;
    _scriptController = SyntaxHighlightController(text: starterTemplate)
      ..addListener(_onScriptChanged);
    _previewController = RenPyFlutterController(
      onDiagnostic: _onRunDiagnostic,
      snapshotStore: RenPyMemoryRunnerSnapshotStore(),
      slotStore: RenPyMemoryRunnerSnapshotSlotStore(),
    )..addListener(_onPreviewAdvanced);
    _parseForDiagnostics(notify: false);
    // Bundled art loads asynchronously so it never blocks the first build;
    // the preview refreshes when the bytes arrive.
    _loadBundledAssets();
    // The preview is live from launch: start the script once the first frame
    // has mounted the player layers, then follow edits and the cursor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasRun) return;
      setState(() => _hasRun = true);
      _reloadPreview(cursorLine: _cursorLine());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _followDebounce?.cancel();
    _editorScrollController.dispose();
    _scriptController.dispose();
    _previewController
      ..removeListener(_onPreviewAdvanced)
      ..dispose();
    _previewAudioPlayback.dispose();
    super.dispose();
  }

  // --- Preview-to-cursor sync -------------------------------------------

  /// Mirrors preview navigation back into the editor: when the player
  /// advances to a new beat, the cursor moves to that statement's line (and
  /// the editor scrolls it into view). [_syncingPreview] keeps the burst of
  /// events from a reload/fast-forward from bouncing back, and
  /// [_previewCursorLine] keeps the cursor-follow path from reloading the
  /// preview we just advanced.
  void _onPreviewAdvanced() {
    if (_syncingPreview || !_hasRun || !mounted) return;
    final status = _previewController.value;
    if (status is! RenPyDialogue && status is! RenPyMenu) return;
    final line = _previewController.currentLine;
    if (line == null || line == _previewCursorLine) return;
    _moveCursorToLine(line);
  }

  /// Places the caret at the end of [line] (1-based) and scrolls it into
  /// view, without marking the document dirty.
  void _moveCursorToLine(int line) {
    _previewCursorLine = line;
    final text = _scriptController.text;
    var offset = 0;
    for (var current = 1; current < line && offset < text.length; current++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) break;
      offset = next + 1;
    }
    final lineEnd = text.indexOf('\n', offset);
    _scriptController.selection = TextSelection.collapsed(
      offset: lineEnd < 0 ? text.length : lineEnd,
    );
    _scrollEditorToLine(line);
  }

  /// Centers [line] in the editor viewport (best effort).
  void _scrollEditorToLine(int line) {
    if (!_editorScrollController.hasClients) return;
    final lineHeight =
        _editorTextStyle.fontSize! * (_editorTextStyle.height ?? 1.5);
    final position = _editorScrollController.position;
    final target = ((line - 1) * lineHeight + 8 -
            position.viewportDimension / 2)
        .clamp(0.0, position.maxScrollExtent);
    _editorScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  // --- Diagnostics -----------------------------------------------------

  void _onScriptChanged() {
    if (_scriptController.text == _lastText) {
      // Selection-only change: follow the cursor in the running preview.
      _scheduleCursorFollow();
      return;
    }
    _lastText = _scriptController.text;
    if (!_suppressDirty) _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(parseDebounce, () {
      _parseForDiagnostics();
      _hotReloadPreview();
    });
    // Rebuild for the live line/character counts.
    setState(() {});
  }

  /// Re-runs the preview after an edit once typing settles ("hot reload"),
  /// bringing it back to the beat at the cursor. Parse errors leave the last
  /// good preview running.
  void _hotReloadPreview() {
    if (!mounted || !_hasRun || _parseError != null) return;
    _reloadPreview(cursorLine: _cursorLine());
  }

  void _scheduleCursorFollow() {
    if (!_hasRun) return;
    _followDebounce?.cancel();
    _followDebounce = Timer(parseDebounce, () {
      if (!mounted || !_hasRun || _parseError != null) return;
      final line = _cursorLine();
      if (line == null || line == _previewCursorLine) return;
      _reloadPreview(cursorLine: line);
    });
  }

  /// The 1-based line the editor cursor is on, or null without a selection.
  int? _cursorLine() {
    final selection = _scriptController.selection;
    if (!selection.isValid) return null;
    final text = _scriptController.text;
    final offset = selection.baseOffset.clamp(0, text.length);
    var line = 1;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  /// The name of the last label declared at or above [line], so the preview
  /// can start from the section the cursor is in.
  String? _labelForLine(int line) {
    final RenPyScript script;
    try {
      script = RenPyParser().parse(_scriptController.text, 'editor.rpy').script;
    } catch (_) {
      return null;
    }
    String? best;
    for (final statement in script.statements) {
      if (statement is RenPyLabelStatement && statement.linenumber <= line) {
        best = statement.name;
      }
    }
    return best;
  }

  /// (Re)loads the preview controller from the current script, starting at
  /// the label enclosing [cursorLine] and fast-forwarding to it.
  void _reloadPreview({int? cursorLine}) {
    _followDebounce?.cancel();
    if (_runDiagnostics.isNotEmpty) {
      setState(() => _runDiagnostics.clear());
    }
    _previewCursorLine = cursorLine ?? 0;
    _syncingPreview = true;
    try {
      _previewController.load(
        _scriptController.text,
        filename: 'editor.rpy',
        gameRoot: 'game',
        availableAssets: {..._assets.keys, ...widget.extraPreviewAssets},
        startLabel: cursorLine == null ? null : _labelForLine(cursorLine),
      );
      if (cursorLine != null) {
        _previewController.fastForwardToLine(cursorLine);
      }
    } catch (error) {
      _previewController.value = RenPyError(error.toString());
    } finally {
      _syncingPreview = false;
    }
  }

  /// Parses the current script for diagnostics only. Never touches the
  /// running preview.
  void _parseForDiagnostics({bool notify = true}) {
    RenPyParseError? error;
    List<String> warnings = const [];
    try {
      final result = RenPyParser().parse(_scriptController.text, 'editor.rpy');
      warnings = result.warnings;
    } on RenPyParseError catch (e) {
      error = e;
    } catch (e) {
      error = RenPyParseError(e.toString(), 'editor.rpy', 1, 0);
    }
    if (!notify) {
      _parseError = error;
      _parseWarnings = warnings;
      return;
    }
    if (!mounted) return;
    setState(() {
      _parseError = error;
      _parseWarnings = warnings;
    });
  }

  void _onRunDiagnostic(RenPyDiagnostic diagnostic) {
    final detail = diagnostic.detail;
    final message =
        detail == null
            ? diagnostic.message
            : '${diagnostic.message} ($detail)';
    if (!mounted) return;
    setState(() => _runDiagnostics.add(message));
  }

  List<_Issue> get _issues => [
    if (_parseError case final error?)
      _Issue(_IssueSeverity.error, 'Line ${error.linenumber}: ${error.message}'),
    for (final warning in _parseWarnings)
      _Issue(_IssueSeverity.warning, warning),
    for (final diagnostic in _runDiagnostics)
      _Issue(_IssueSeverity.warning, diagnostic),
  ];

  // --- Toolbar actions -------------------------------------------------

  void _run() {
    _debounce?.cancel();
    _parseForDiagnostics(notify: false);
    setState(() {
      _hasRun = true;
      _runDiagnostics.clear();
      _activeTab = 1;
    });
    _reloadPreview(cursorLine: _cursorLine());
  }

  /// Asks the user to confirm discarding unsaved changes. Returns true when
  /// the document is clean or the user chose Discard.
  Future<bool> _confirmDiscard(String message) async {
    if (!_dirty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    return confirmed == true;
  }

  Future<void> _newScript() async {
    final confirmed = await _confirmDiscard(
      'The editor has unsaved changes. Replace them with the '
      'starter template?',
    );
    if (!confirmed) return;
    _setScript(starterTemplate);
  }

  /// Loads a bundled example: confirm-if-dirty, replace the script, clear
  /// session assets, then run the same migration-report flow as opening a
  /// `.rpy` file.
  Future<void> _loadExample(EditorExample example) async {
    final confirmed = await _confirmDiscard(
      'The editor has unsaved changes. Replace them with '
      '"${example.label}"?',
    );
    if (!confirmed) return;

    String text;
    try {
      text = await example.load();
    } catch (error) {
      _showSnackBar('Could not load ${example.label}: $error');
      return;
    }
    // Defensive: some upstream scripts ship with a UTF-8 BOM.
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    FlyMigrationReport? report;
    try {
      report = runRpyToFlyGate(text, filename: '${example.id}.rpy').report;
    } catch (_) {
      // Parse failure — will show in the diagnostics strip instead.
    }

    _setScript(text);

    if (report != null && report.issues.isNotEmpty && mounted) {
      await showMigrationReportDialog(
        context,
        report,
        title: 'Loaded ${example.label}',
        confirmLabel: 'OK',
      );
    }
  }

  Future<void> _open() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['rpy', 'fly', 'zip', 'txt'],
        withData: true,
      );
    } catch (error) {
      _showSnackBar('Could not open a file: $error');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _showSnackBar('Could not read "${file.name}".');
      return;
    }

    final name = file.name.toLowerCase();
    if (name.endsWith('.fly.zip') || name.endsWith('.zip')) {
      await _openFlyZip(file.name, bytes);
      return;
    }

    final String source;
    try {
      source = utf8.decode(bytes);
    } catch (_) {
      _showSnackBar('"${file.name}" is not a UTF-8 text file.');
      return;
    }

    String text = source;
    FlyMigrationReport? report;

    if (name.endsWith('.fly')) {
      try {
        final script = const FlyCodec().decodeFromString(
          source,
          filename: file.name,
        );
        text = const RenPyEmitter().emitScript(script);
      } on FlyFormatException catch (error) {
        _showSnackBar('Could not read ${file.name}: ${error.message}');
        return;
      } catch (error) {
        _showSnackBar('Could not read ${file.name}: $error');
        return;
      }
    } else if (name.endsWith('.rpy')) {
      // Run migration gate to surface what would be lost in a .fly round-trip.
      try {
        final gate = runRpyToFlyGate(source, filename: file.name);
        report = gate.report;
      } catch (_) {
        // Parse failure — will show in the diagnostics strip instead.
      }
    }

    _setScript(text);

    if (report != null && report.issues.isNotEmpty && mounted) {
      await showMigrationReportDialog(
        context,
        report,
        title: 'Opened ${file.name}',
        confirmLabel: 'OK',
      );
    }
  }

  Future<void> _openFlyZip(String filename, Uint8List bytes) async {
    final FlyArchive archive;
    try {
      archive = FlyArchive.decode(bytes);
    } on FlyArchiveException catch (error) {
      _showSnackBar('Could not open $filename: ${error.message}');
      return;
    }

    String text;
    try {
      text = archive.scriptAsRpy();
    } on FlyFormatException catch (error) {
      _showSnackBar('Could not read script in $filename: ${error.message}');
      return;
    }

    _setScript(
      text,
      assets: {
        for (final file in archive.files)
          if (file.path != archive.scriptPath) file.path: file.bytes,
      },
    );

    if (archive.notes.isNotEmpty) {
      _showSnackBar(archive.notes.join('; '));
    }
  }

  // --- Session asset management ------------------------------------------

  /// Loads the bundled example art into the session. New entries never
  /// overwrite assets the user already added under the same path.
  Future<void> _loadBundledAssets() async {
    final loader = widget.loadBundledAssets ?? loadBundledExampleAssets;
    final Map<String, Uint8List> loaded;
    try {
      loaded = await loader();
    } catch (_) {
      // Missing bundled art is not fatal — previews fall back to
      // placeholders, exactly as before the art shipped.
      return;
    }
    if (!mounted || loaded.isEmpty) return;
    _bundledAssets = loaded;
    setState(() {
      for (final entry in loaded.entries) {
        _assets.putIfAbsent(entry.key, () => entry.value);
      }
    });
    _refreshPreviewAssets();
  }

  /// Default "Add…" implementation: any file type, multiple, with bytes.
  static Future<List<PickedAssetFile>?> _pickAssetFilesWithFilePicker() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return null;
    return [
      for (final file in result.files)
        if (file.bytes case final bytes?) (name: file.name, bytes: bytes),
    ];
  }

  /// Adds [files] to the session under their conventional `game/` paths and
  /// pushes the new asset set into the running preview.
  void addSessionAssets(List<PickedAssetFile> files) {
    if (files.isEmpty) return;
    setState(() {
      for (final file in files) {
        _assets[sessionAssetPathFor(file.name)] = file.bytes;
      }
    });
    _refreshPreviewAssets();
  }

  /// Removes the asset stored at [path] and updates the running preview.
  void removeSessionAsset(String path) {
    setState(() => _assets.remove(path));
    _refreshPreviewAssets();
  }

  /// Re-runs the preview so `availableAssets` reflects the current session
  /// assets. Leaves a parse-broken preview alone, like hot reload does.
  void _refreshPreviewAssets() {
    if (!_hasRun || _parseError != null) return;
    _reloadPreview(cursorLine: _cursorLine());
  }

  Future<void> _addAssetsFromPicker() async {
    final picker = widget.pickAssets ?? _pickAssetFilesWithFilePicker;
    final List<PickedAssetFile>? picked;
    try {
      picked = await picker();
    } catch (error) {
      _showSnackBar('Could not add files: $error');
      return;
    }
    if (picked == null || picked.isEmpty) return;
    addSessionAssets(picked);
  }

  Future<void> _showAssetsPanel() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // StatefulBuilder so Add/Remove refresh the open dialog; the screen
        // itself is refreshed by addSessionAssets/removeSessionAsset.
        return StatefulBuilder(
          builder: (dialogContext, panelSetState) {
            final paths = _assets.keys.toList()..sort();
            return AlertDialog(
              key: const ValueKey('editor-assets-panel'),
              title: Row(
                children: [
                  const Expanded(child: Text('Session assets')),
                  FilledButton.tonalIcon(
                    key: const ValueKey('editor-assets-add-button'),
                    onPressed: () async {
                      await _addAssetsFromPicker();
                      panelSetState(() {});
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add…'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _assetReferenceHint,
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(color: Colors.white54),
                    ),
                    const SizedBox(height: 12),
                    if (paths.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No session assets yet. Add images or audio, or '
                          'open a .fly.zip.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final path in paths)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(_assetKindIcon(path), size: 20),
                                title: Text(
                                  path,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  _formatByteSize(_assets[path]!.length),
                                ),
                                trailing: IconButton(
                                  key: ValueKey('editor-asset-remove-$path'),
                                  tooltip: 'Remove',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    removeSessionAsset(path);
                                    panelSetState(() {});
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('editor-assets-close-button'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// How scripts reach session assets — matches `RenPyImageResolver` (images
  /// try `game/<name>.<ext>` then `game/images/<name>.<ext>` for
  /// png/jpg/jpeg/webp/gif, spaces matching underscores, then any file under
  /// `game/` with that base name) and `RenPyAudioAssetResolver` (audio paths
  /// are joined onto `game/` verbatim).
  static const String _assetReferenceHint =
      'Reference images by bare name: "show sylvie" finds '
      'game/images/sylvie.png (or .jpg/.jpeg/.webp/.gif, also directly under '
      'game/, or any game/ file named sylvie; spaces match underscores, so '
      '"scene bg meadow" finds bg_meadow.png). Reference audio relative to '
      'game/: \'play music "audio/track.ogg"\'.';

  static IconData _assetKindIcon(String path) {
    final dot = path.lastIndexOf('.');
    final extension = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    if (const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(extension)) {
      return Icons.image_outlined;
    }
    if (const {'ogg', 'opus', 'mp3', 'wav'}.contains(extension)) {
      return Icons.audiotrack_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  static String _formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // --- Character gallery ---------------------------------------------------

  /// Inserts [statements] as new lines below the editor's cursor line, each
  /// indented to match the surrounding block, and parks the caret at the end
  /// of the insertion. The controller listener then runs the normal change
  /// pipeline (dirty flag, debounced parse, hot reload at the new cursor).
  void _insertStatementsAtCursor(List<String> statements) {
    if (statements.isEmpty) return;
    final text = _scriptController.text;
    final selection = _scriptController.selection;
    final offset = (selection.isValid ? selection.baseOffset : text.length)
        .clamp(0, text.length);
    final lineStart = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
    var lineEnd = text.indexOf('\n', offset);
    if (lineEnd < 0) lineEnd = text.length;
    final indent = _insertionIndent(text, lineStart);
    final insertion = [
      for (final statement in statements) '$indent$statement',
    ].join('\n');
    _scriptController.value = TextEditingValue(
      text: '${text.substring(0, lineEnd)}\n$insertion${text.substring(lineEnd)}',
      selection: TextSelection.collapsed(offset: lineEnd + 1 + insertion.length),
    );
  }

  /// The indentation for a statement inserted below the line starting at
  /// [lineStart]: the nearest non-blank line at or above the cursor sets the
  /// level, one level (four spaces) deeper when that line opens a block with
  /// a trailing `:`. Defaults to one level in an all-blank document.
  static String _insertionIndent(String text, int lineStart) {
    var start = lineStart;
    while (true) {
      var end = text.indexOf('\n', start);
      if (end < 0) end = text.length;
      final line = text.substring(start, end);
      if (line.trim().isNotEmpty) {
        final indent = RegExp(r'^ *').firstMatch(line)!.group(0)!;
        return line.trimRight().endsWith(':') ? '$indent    ' : indent;
      }
      if (start == 0) return '    ';
      start = start < 2 ? 0 : text.lastIndexOf('\n', start - 2) + 1;
    }
  }

  /// Closes the gallery dialog and inserts [statements] at the cursor line.
  void _insertFromGallery(BuildContext dialogContext, List<String> statements) {
    Navigator.of(dialogContext).pop();
    _insertStatementsAtCursor(statements);
  }

  /// The character gallery: session images grouped into characters and
  /// backgrounds by filename convention, with tap-to-insert thumbnails,
  /// at-left/center/right placement shortcuts, and a two-character helper.
  Future<void> _showCharacterGallery() async {
    String? pairLeft;
    String? pairRight;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // StatefulBuilder so the two-character dropdowns refresh in place.
        return StatefulBuilder(
          builder: (dialogContext, panelSetState) {
            final gallery = groupGalleryImages(_assets.keys);
            final tags = gallery.characters.keys.toList()..sort();
            final variantNames = [
              for (final tag in tags)
                for (final image in gallery.characters[tag]!) image.showName,
            ];
            final theme = Theme.of(dialogContext);
            // A host-provided section (e.g. Spine characters) keeps the
            // gallery meaningful even when no image assets are loaded.
            final extraSection = widget.extraGallerySection?.call(
              dialogContext,
              (statements) => _insertFromGallery(dialogContext, statements),
            );
            final isEmpty =
                tags.isEmpty &&
                gallery.backgrounds.isEmpty &&
                extraSection == null;
            return AlertDialog(
              key: const ValueKey('editor-gallery-panel'),
              title: const Text('Character gallery'),
              content: SizedBox(
                width: 640,
                child:
                    isEmpty
                        ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No image assets yet. Add images named like '
                            '"sylvie green smile.png" or "bg meadow.jpg" '
                            'via the Assets panel.',
                            textAlign: TextAlign.center,
                          ),
                        )
                        : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tap a sprite to insert "show …" at the '
                                'cursor; L / C / R place it at left, center, '
                                'or right. Backgrounds insert "scene …".',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final tag in tags) ...[
                                Text(tag, style: theme.textTheme.titleSmall),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final image
                                        in gallery.characters[tag]!)
                                      _galleryCharacterTile(
                                        dialogContext,
                                        image,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (variantNames.length >= 2) ...[
                                Text(
                                  'Two characters',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Insert a pair of shows at left and right, '
                                  'ready for back-and-forth dialogue.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButton<String>(
                                        key: const ValueKey(
                                          'editor-gallery-pair-left',
                                        ),
                                        isExpanded: true,
                                        hint: const Text('Left character'),
                                        value: pairLeft,
                                        items: [
                                          for (final name in variantNames)
                                            DropdownMenuItem(
                                              key: ValueKey(
                                                'editor-gallery-pair-left-'
                                                '$name',
                                              ),
                                              value: name,
                                              child: Text(name),
                                            ),
                                        ],
                                        onChanged:
                                            (value) => panelSetState(
                                              () => pairLeft = value,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: DropdownButton<String>(
                                        key: const ValueKey(
                                          'editor-gallery-pair-right',
                                        ),
                                        isExpanded: true,
                                        hint: const Text('Right character'),
                                        value: pairRight,
                                        items: [
                                          for (final name in variantNames)
                                            DropdownMenuItem(
                                              key: ValueKey(
                                                'editor-gallery-pair-right-'
                                                '$name',
                                              ),
                                              value: name,
                                              child: Text(name),
                                            ),
                                        ],
                                        onChanged:
                                            (value) => panelSetState(
                                              () => pairRight = value,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.tonal(
                                      key: const ValueKey(
                                        'editor-gallery-pair-insert',
                                      ),
                                      onPressed:
                                          pairLeft == null || pairRight == null
                                              ? null
                                              : () => _insertFromGallery(
                                                dialogContext,
                                                [
                                                  'show $pairLeft at left',
                                                  'show $pairRight at right',
                                                ],
                                              ),
                                      child: const Text('Insert pair'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (gallery.backgrounds.isNotEmpty) ...[
                                Text(
                                  'Backgrounds',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final image in gallery.backgrounds)
                                      _galleryThumb(
                                        dialogContext,
                                        key: ValueKey(
                                          'editor-gallery-scene-'
                                          '${image.showName}',
                                        ),
                                        bytes: _assets[image.path]!,
                                        label:
                                            image.variant.isEmpty
                                                ? image.tag
                                                : image.variant,
                                        tooltip:
                                            'Insert "scene ${image.showName}"',
                                        onTap:
                                            () => _insertFromGallery(
                                              dialogContext,
                                              ['scene ${image.showName}'],
                                            ),
                                      ),
                                  ],
                                ),
                              ],
                              if (extraSection != null) ...[
                                const SizedBox(height: 16),
                                extraSection,
                              ],
                            ],
                          ),
                        ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('editor-gallery-close-button'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// A character variant tile: the thumbnail inserts a plain `show`, and the
  /// L / C / R shortcuts underneath insert `show … at left|center|right`.
  Widget _galleryCharacterTile(BuildContext dialogContext, GalleryImage image) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _galleryThumb(
          dialogContext,
          key: ValueKey('editor-gallery-show-${image.showName}'),
          bytes: _assets[image.path]!,
          label: image.variant.isEmpty ? image.tag : image.variant,
          tooltip: 'Insert "show ${image.showName}"',
          onTap:
              () =>
                  _insertFromGallery(dialogContext, ['show ${image.showName}']),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final position in const ['left', 'center', 'right'])
              Tooltip(
                message: 'Insert "show ${image.showName} at $position"',
                child: InkWell(
                  key: ValueKey(
                    'editor-gallery-show-${image.showName}-$position',
                  ),
                  borderRadius: BorderRadius.circular(4),
                  onTap:
                      () => _insertFromGallery(dialogContext, [
                        'show ${image.showName} at $position',
                      ]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      position.substring(0, 1).toUpperCase(),
                      style: Theme.of(dialogContext).textTheme.labelSmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// A small tappable thumbnail (72×72 [Image.memory]) with a caption.
  Widget _galleryThumb(
    BuildContext dialogContext, {
    required Key key,
    required Uint8List bytes,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF202020),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 80,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(dialogContext).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveFly() async {
    final FlyMigrationResult gate;
    try {
      gate = runRpyToFlyGate(_scriptController.text);
    } on RenPyParseError catch (error) {
      _showSnackBar('Cannot save: $error');
      return;
    }

    if (!gate.report.isFaithful && mounted) {
      final proceed = await showMigrationReportDialog(
        context,
        gate.report,
        title: 'Save .fly',
        confirmLabel: 'Save Anyway',
        cancelLabel: 'Cancel',
      );
      if (proceed != true) return;
    }

    await saveTextFile('story.fly', gate.output);
    _dirty = false;
  }

  Future<void> _saveFlyZip() async {
    final Uint8List zipBytes;
    try {
      zipBytes = FlyArchive.fromScript(
        scriptSource: _scriptController.text,
        assets: [
          for (final entry in _assets.entries)
            FlyArchiveFile(entry.key, entry.value),
        ],
      );
    } on FlyArchiveException catch (error) {
      _showSnackBar('Cannot package: ${error.message}');
      return;
    } on RenPyParseError catch (error) {
      _showSnackBar('Cannot package: $error');
      return;
    }

    // Show migration fidelity before writing.
    try {
      final gate = runRpyToFlyGate(_scriptController.text);
      if (!gate.report.isFaithful && mounted) {
        final proceed = await showMigrationReportDialog(
          context,
          gate.report,
          title: 'Save .fly.zip',
          confirmLabel: 'Save Anyway',
          cancelLabel: 'Cancel',
        );
        if (proceed != true) return;
      }
    } catch (_) {
      // Gate already passed if fromScript succeeded; swallow.
    }

    await saveBinaryFile('story.fly.zip', zipBytes);
    _dirty = false;
  }

  Future<void> _exportRpy() async {
    await saveTextFile('script.rpy', _scriptController.text);
    _dirty = false;
  }

  void _setScript(String text, {Map<String, Uint8List> assets = const {}}) {
    // Replacing the session keeps the bundled example art available (an
    // opened archive's own files win on path conflicts).
    _assets
      ..clear()
      ..addAll(_bundledAssets)
      ..addAll(assets);
    _suppressDirty = true;
    _scriptController.text = text;
    _suppressDirty = false;
    _dirty = false;
    _debounce?.cancel();
    setState(() => _activeTab = 0);
    _parseForDiagnostics();
    if (_hasRun && _parseError == null) _reloadPreview();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(context),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < _narrowBreakpoint) {
                    return _buildNarrowBody(context);
                  }
                  return _buildWideBody(context, constraints);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('editor-new-button'),
                    onPressed: _newScript,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('New'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('editor-open-button'),
                    onPressed: _open,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Open…'),
                  ),
                  PopupMenuButton<EditorExample>(
                    key: const ValueKey('editor-examples-button'),
                    tooltip: 'Load an example story',
                    onSelected: _loadExample,
                    itemBuilder:
                        (context) => [
                          for (final example in [
                            ...editorExamples,
                            ...widget.extraExamples,
                          ])
                            PopupMenuItem(
                              key: ValueKey(
                                'editor-example-${example.id}',
                              ),
                              value: example,
                              child: Text(example.label),
                            ),
                        ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Examples ▾',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('editor-assets-button'),
                    onPressed: _showAssetsPanel,
                    icon: const Icon(Icons.collections_outlined, size: 18),
                    label: const Text('Assets'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('editor-gallery-button'),
                    onPressed: _showCharacterGallery,
                    icon: const Icon(Icons.people_alt_outlined, size: 18),
                    label: const Text('Characters'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('editor-save-fly-button'),
                    onPressed: _saveFly,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save .fly'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('editor-save-flyzip-button'),
                    onPressed: _saveFlyZip,
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Save .fly.zip'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('editor-export-rpy-button'),
                    onPressed: _exportRpy,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Export .rpy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('editor-run-button'),
                    onPressed: _run,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Run'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildAssetsChip(context),
          const SizedBox(width: 8),
          _buildStatusChip(context),
        ],
      ),
    );
  }

  /// Always-visible count of session assets; tapping it opens the panel.
  Widget _buildAssetsChip(BuildContext context) {
    final count = _assets.length;
    return InkWell(
      onTap: _showAssetsPanel,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        key: const ValueKey('editor-assets-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.collections_outlined,
                size: 12, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              count == 1 ? '1 asset' : '$count assets',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final issueCount = _issues.length;
    final Color color;
    final String label;
    if (issueCount > 0) {
      final hasError = _parseError != null;
      color = hasError ? Colors.redAccent : Colors.amber;
      label = issueCount == 1 ? '1 issue' : '$issueCount issues';
    } else if (_hasRun) {
      color = Colors.greenAccent;
      label = 'Running';
    } else {
      color = Colors.grey;
      label = 'Idle';
    }
    return Container(
      key: const ValueKey('editor-status-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _buildWideBody(BuildContext context, BoxConstraints constraints) {
    const dividerWidth = 8.0;
    final available = constraints.maxWidth - dividerWidth;
    final editorWidth = available * _splitRatio;
    return Row(
      children: [
        SizedBox(width: editorWidth, child: _buildEditorPane(context)),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: const ValueKey('editor-splitter'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              setState(() {
                _splitRatio = ((editorWidth + details.delta.dx) / available)
                    .clamp(0.2, 0.8);
              });
            },
            child: Container(
              width: dividerWidth,
              color: const Color(0xFF1A1A1A),
              child: Center(
                child: Container(
                  width: 2,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _buildPreviewPane(context)),
      ],
    );
  }

  Widget _buildNarrowBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Editor'),
                icon: Icon(Icons.edit_note),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Preview'),
                icon: Icon(Icons.smart_display_outlined),
              ),
            ],
            selected: {_activeTab},
            onSelectionChanged:
                (selection) => setState(() => _activeTab = selection.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _activeTab,
            children: [
              _buildEditorPane(context),
              _buildPreviewPane(context),
            ],
          ),
        ),
      ],
    );
  }

  static const _editorTextStyle = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Courier New', 'Courier'],
    fontSize: 14,
    height: 1.5,
  );

  Widget _buildEditorPane(BuildContext context) {
    final issues = _issues;
    final lineCount = '\n'.allMatches(_scriptController.text).length + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF161616),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LineNumberGutter(
                  lineCount: lineCount,
                  scrollController: _editorScrollController,
                  textStyle: _editorTextStyle,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    child: TextField(
                      key: const ValueKey('editor-script-field'),
                      controller: _scriptController,
                      scrollController: _editorScrollController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      style: _editorTextStyle,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildEditorStatusBar(context),
        if (issues.isNotEmpty) _buildIssuesStrip(context, issues),
      ],
    );
  }

  Widget _buildEditorStatusBar(BuildContext context) {
    final text = _scriptController.text;
    final lines = '\n'.allMatches(text).length + 1;
    final String parseState;
    if (_parseError != null) {
      parseState = 'Parse error';
    } else if (_parseWarnings.isNotEmpty) {
      parseState =
          _parseWarnings.length == 1
              ? '1 warning'
              : '${_parseWarnings.length} warnings';
    } else {
      parseState = 'OK';
    }
    return Container(
      key: const ValueKey('editor-status-bar'),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          Text(
            '$lines lines · ${text.length} chars',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Spacer(),
          Text(
            parseState,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color:
                  _parseError != null
                      ? Colors.redAccent
                      : _parseWarnings.isNotEmpty
                      ? Colors.amber
                      : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssuesStrip(BuildContext context, List<_Issue> issues) {
    return Container(
      key: const ValueKey('editor-issues-strip'),
      constraints: const BoxConstraints(maxHeight: 110),
      color: const Color(0xFF1D1414),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: issues.length,
        itemBuilder: (context, index) {
          final issue = issues[index];
          final isError = issue.severity == _IssueSeverity.error;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.warning_amber_outlined,
                  size: 14,
                  color: isError ? Colors.redAccent : Colors.amber,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    issue.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isError ? Colors.redAccent : Colors.amber,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewPane(BuildContext context) {
    if (!_hasRun) {
      return Container(
        key: const ValueKey('editor-preview-placeholder'),
        color: const Color(0xFF121212),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline,
                  size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              Text(
                'Press ▶ Run to preview your story',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }
    final screenSize = RenPyScreenSize.fromScriptSource(_scriptController.text);
    return RenPyPlayer(
      controller: _previewController,
      backgroundColor: const Color(0xFF121212),
      audioPlayback: widget.audioPlayback ?? _previewAudioPlayback,
      preferenceStore: _preferenceStore,
      showRestartButton: true,
      onRestart: _run,
      gameRoot: 'game',
      screenSize: screenSize,
      dialogueImageProvider: _previewImageProvider,
      screenImageProvider: _previewImageProvider,
      imageLayerBuilder: (context, controller) {
        final builder = widget.imageLayerBuilder;
        if (builder != null) {
          return builder(
            context,
            controller,
            screenSize ?? RenPyScreenSize.fallback,
            _previewImageProvider,
          );
        }
        return RenPyImageLayer(
          controller: controller,
          imageProvider: _previewImageProvider,
          screenSize: screenSize ?? RenPyScreenSize.fallback,
          atlResolver: controller.resolveAtl,
        );
      },
    );
  }

  /// Plays preview audio from the session assets (bundled example music and
  /// .fly.zip tracks live in [_assets], not the Flutter asset bundle, so the
  /// player's default bundle-backed playback would 404).
  late final RenPyBytesAudioPlayback _previewAudioPlayback =
      RenPyBytesAudioPlayback(const {}, readAsset: (path) => _assets[path]);

  /// Resolves preview image paths against the opened archive's assets,
  /// falling back to Flutter bundle assets for paths we don't carry.
  ImageProvider<Object> _previewImageProvider(String assetPath) {
    final bytes = _assets[assetPath];
    if (bytes == null) return AssetImage(assetPath);
    return MemoryImage(bytes);
  }
}

class _LineNumberGutter extends StatefulWidget {
  const _LineNumberGutter({
    required this.lineCount,
    required this.scrollController,
    required this.textStyle,
  });

  final int lineCount;
  final ScrollController scrollController;
  final TextStyle textStyle;

  @override
  State<_LineNumberGutter> createState() => _LineNumberGutterState();
}

class _LineNumberGutterState extends State<_LineNumberGutter> {
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _LineNumberGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pos = widget.scrollController.position;
    if (pos.hasPixels && _offset != pos.pixels) {
      setState(() => _offset = pos.pixels);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = widget.lineCount.toString().length;
    final charWidth = digits.clamp(2, 6);
    final gutterWidth = 12.0 + charWidth * 8.6;
    final lineHeight =
        widget.textStyle.fontSize! * (widget.textStyle.height ?? 1.5);
    return SizedBox(
      width: gutterWidth,
      child: ClipRect(
        child: CustomPaint(
          painter: _LineNumberPainter(
            lineCount: widget.lineCount,
            scrollOffset: _offset,
            lineHeight: lineHeight,
            gutterWidth: gutterWidth,
          ),
        ),
      ),
    );
  }
}

class _LineNumberPainter extends CustomPainter {
  _LineNumberPainter({
    required this.lineCount,
    required this.scrollOffset,
    required this.lineHeight,
    required this.gutterWidth,
  });

  final int lineCount;
  final double scrollOffset;
  final double lineHeight;
  final double gutterWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 8.0; // matches contentPadding vertical
    final firstVisible = ((scrollOffset - topPad) / lineHeight).floor().clamp(0, lineCount - 1);
    final lastVisible = ((scrollOffset - topPad + size.height) / lineHeight).ceil().clamp(0, lineCount);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = firstVisible; i < lastVisible; i++) {
      tp.text = TextSpan(
        text: '${i + 1}',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: ['Courier New', 'Courier'],
          fontSize: 14,
          height: 1.5,
          color: Color(0xFF555555),
        ),
      );
      tp.layout();
      final y = topPad + i * lineHeight - scrollOffset;
      tp.paint(canvas, Offset(gutterWidth - tp.width - 8, y));
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_LineNumberPainter oldDelegate) =>
      lineCount != oldDelegate.lineCount ||
      scrollOffset != oldDelegate.scrollOffset ||
      lineHeight != oldDelegate.lineHeight ||
      gutterWidth != oldDelegate.gutterWidth;
}
