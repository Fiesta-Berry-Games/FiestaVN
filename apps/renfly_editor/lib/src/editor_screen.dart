import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

enum _IssueSeverity { error, warning }

final class _Issue {
  const _Issue(this.severity, this.message);

  final _IssueSeverity severity;
  final String message;
}

/// The single-screen IDE: toolbar, script editor, and live preview.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.audioPlayback});

  /// Optional audio backend override for the preview player (tests inject
  /// [RenPyNoOpAudioPlayback]).
  final RenPyAudioPlayback? audioPlayback;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _scriptController;
  late final ScrollController _editorScrollController;
  late final RenPyFlutterController _previewController;

  /// Memory-only stores so editor preview runs never pollute persisted saves.
  final RenPyMemoryPreferenceStore _preferenceStore =
      RenPyMemoryPreferenceStore();

  /// Assets bundled with the opened script (from a `.fly.zip`), keyed by
  /// archive path (e.g. `game/images/bg.png`). The preview resolves images
  /// from here so characters and backgrounds actually display.
  final Map<String, Uint8List> _assets = {};

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
        availableAssets: _assets.keys.toSet(),
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

  Future<void> _newScript() async {
    if (_dirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Discard changes?'),
              content: const Text(
                'The editor has unsaved changes. Replace them with the '
                'starter template?',
              ),
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
      if (confirmed != true) return;
    }
    _setScript(starterTemplate);
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
    _assets
      ..clear()
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
            'RenFly Editor',
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
          _buildStatusChip(context),
        ],
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
      audioPlayback: widget.audioPlayback,
      preferenceStore: _preferenceStore,
      showRestartButton: true,
      onRestart: _run,
      gameRoot: 'game',
      screenSize: screenSize,
      dialogueImageProvider: _previewImageProvider,
      screenImageProvider: _previewImageProvider,
      imageLayerBuilder: (context, controller) {
        return RenPyImageLayer(
          controller: controller,
          imageProvider: _previewImageProvider,
          screenSize: screenSize ?? RenPyScreenSize.fallback,
          atlResolver: controller.resolveAtl,
        );
      },
    );
  }

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
