import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly_editor/main.dart';
import 'package:renfly_editor/src/editor_screen.dart';
import 'package:renfly_editor/src/migration_report.dart';
import 'package:renfly_editor/src/starter_template.dart';
import 'package:renfly_editor/src/syntax_highlight.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/renpy_writer.dart';

/// Pumps frames until [condition] holds, failing after [attempts] pumps.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 100,
  String description = 'condition',
}) async {
  for (var i = 0; i < attempts; i += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description');
}

/// Pumps the editor with an injected bundled-art loader ([bundledAssets],
/// empty by default) so no real asset I/O runs inside the fake-async zone.
Future<void> pumpEditor(
  WidgetTester tester, {
  PickAssetFiles? pickAssets,
  Map<String, Uint8List> bundledAssets = const {},
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RenFlyEditorApp(
      audioPlayback: const RenPyNoOpAudioPlayback(),
      pickAssets: pickAssets,
      loadBundledAssets: () async => bundledAssets,
    ),
  );
  await tester.pump();
}

/// A valid 1x1 PNG, so MemoryImage-backed previews decode cleanly in tests.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
  'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// In-memory stand-in for the bundled The Question art: the real session
/// paths, with [tinyPng] bytes for images and placeholder bytes for audio.
final Map<String, Uint8List> fakeBundledAssets = {
  for (final path in bundledExampleAssetFiles)
    path: path.endsWith('.opus') ? Uint8List.fromList([1, 2, 3]) : tinyPng,
};

/// The number of [fakeBundledAssets], as the assets chip reports it.
final String bundledAssetCount = '${fakeBundledAssets.length} assets';

void main() {
  testWidgets('app builds with toolbar and the starter template loaded', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('RenFly Editor'), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-new-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-open-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-save-fly-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-export-rpy-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-run-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-status-chip')), findsOneWidget);

    // The starter template is loaded into the editor.
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('editor-script-field')),
    );
    expect(field.controller?.text, starterTemplate);

    // The preview is live from launch: no placeholder, status Running, and
    // the starter's first dialogue line appears (its text also exists in the
    // editor's TextField, so wait for a second occurrence).
    expect(
      find.byKey(const ValueKey('editor-preview-placeholder')),
      findsNothing,
    );
    expect(find.text('Running'), findsOneWidget);
    await pumpUntil(
      tester,
      () =>
          find.textContaining('Welcome to RenFly Editor.').evaluate().length >=
          2,
      description: 'auto-started preview',
    );
  });

  testWidgets('invalid script surfaces a parse error after the debounce', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Tab indentation is a hard Ren'Py parse error.
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n\t"a"\n  x',
    );
    // No error yet: the parse is debounced.
    expect(find.byKey(const ValueKey('editor-issues-strip')), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('editor-issues-strip')), findsOneWidget);
    expect(find.textContaining('Tab characters'), findsWidgets);
    expect(find.text('1 issue'), findsOneWidget);

    // A merely-suspicious script downgrades to an amber warning.
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "a"\n    bogus statement here',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('editor-issues-strip')), findsOneWidget);
    expect(find.textContaining('Warning'), findsWidgets);
  });

  testWidgets('Run plays the starter template in the preview pane', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('editor-run-button')));
    await tester.pump();

    // The placeholder is replaced by the player.
    expect(
      find.byKey(const ValueKey('editor-preview-placeholder')),
      findsNothing,
    );

    // The first dialogue line appears in the preview. The same text also
    // exists in the editor's TextField, so wait for a second occurrence.
    await pumpUntil(
      tester,
      () =>
          find
              .textContaining('Welcome to RenFly Editor.')
              .evaluate()
              .length >=
          2,
      attempts: 200,
      description: 'first dialogue line in the preview',
    );
  });

  testWidgets('edits hot-reload the running preview to the cursor', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n    "Beta"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-run-button')));
    await tester.pump();

    // enterText leaves the cursor at the end of the script, so the preview
    // fast-forwards past "Alpha" to the beat at the cursor.
    await pumpUntil(
      tester,
      () => find.textContaining('Beta').evaluate().length >= 2,
      description: 'preview fast-forwarded to the cursor',
    );

    // Typing more dialogue hot-reloads the running preview without pressing
    // Run again.
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n    "Beta"\n    "Gamma"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntil(
      tester,
      () => find.textContaining('Gamma').evaluate().length >= 2,
      description: 'hot-reloaded preview at the new cursor',
    );
  });

  testWidgets('moving the cursor refocuses the running preview', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n    "Beta"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-run-button')));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.textContaining('Beta').evaluate().length >= 2,
      description: 'preview at the cursor line',
    );

    // Move the cursor into the "Alpha" line without editing the text.
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('editor-script-field')),
    );
    field.controller!.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntil(
      tester,
      () => find.textContaining('Alpha').evaluate().length >= 2,
      description: 'preview following the cursor back to Alpha',
    );
  });

  testWidgets('advancing the preview moves the editor cursor forward', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n    "Beta"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Park the cursor on the "Alpha" line; the preview follows it there.
    final controller =
        tester
            .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
            .controller!;
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(
      tester,
      () => find.textContaining('Alpha').evaluate().length >= 2,
      description: 'preview at Alpha',
    );

    // Advance the preview by tapping the stage; the cursor should land on
    // the "Beta" line (line 3).
    await tester.tap(find.byKey(const ValueKey('renpy-player-stage')));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.textContaining('Beta').evaluate().length >= 2,
      description: 'preview advanced to Beta',
    );

    final offset = controller.selection.baseOffset;
    final line = '\n'.allMatches(controller.text.substring(0, offset)).length + 1;
    expect(line, 3);
  });

  test('starter template round-trips through FlyCodec', () {
    final script =
        RenPyParser().parse(starterTemplate, 'editor.rpy').script;

    const codec = FlyCodec();
    final encoded = codec.encodeToString(script);
    final decoded = codec.decodeFromString(encoded, filename: 'story.fly');

    final emitted = const RenPyEmitter().emitScript(decoded);
    expect(emitted, contains('label start'));

    final reparsed = RenPyParser().parse(emitted, 'roundtrip.rpy').script;
    expect(reparsed.statements.length, script.statements.length);
  });

  testWidgets('toolbar shows Save .fly.zip button', (tester) async {
    await pumpEditor(tester);
    expect(
      find.byKey(const ValueKey('editor-save-flyzip-button')),
      findsOneWidget,
    );
  });

  testWidgets('line number gutter is visible', (tester) async {
    await pumpEditor(tester);
    // The gutter paints via CustomPaint — verify it's present in the tree.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('SyntaxHighlightController colors keywords', () {
    final controller = SyntaxHighlightController(text: 'show bg black');
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    // 'show' is a keyword and should appear as a colored child span.
    final children = span.children!;
    expect(children, isNotEmpty);
    final showSpan = children.firstWhere(
      (s) => (s as TextSpan).text == 'show',
    ) as TextSpan;
    expect(showSpan.style?.color, isNotNull);
  });

  test('runRpyToFlyGate produces faithful result for starter template', () {
    final result = runRpyToFlyGate(starterTemplate);
    expect(result.report.isFaithful, isTrue);
    expect(result.output, isNotEmpty);
  });

  test('runRpyToFlyGate reports issues for unstructured constructs', () {
    const script = 'label start:\n    frobnicate the widget\n    "Hello"\n';
    final result = runRpyToFlyGate(script);
    // An unknown construct stays unstructured and must surface in the report.
    expect(result.report.issues, isNotEmpty);
  });

  testWidgets('MigrationReportDialog renders faithful headline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () => showMigrationReportDialog(
                  context,
                  const FlyMigrationReport([]),
                  title: 'Test',
                ),
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.text('Test'), findsOneWidget);
    expect(find.textContaining('Fully faithful'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('migration-report-confirm')),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------------
  // Status bar: line/char counts
  // ---------------------------------------------------------------

  testWidgets('status bar shows correct line and char counts', (tester) async {
    await pumpEditor(tester);

    // The starter template is loaded; verify the status bar shows its stats.
    final starterLines =
        '\n'.allMatches(starterTemplate).length + 1;
    final starterChars = starterTemplate.length;
    expect(
      find.textContaining('$starterLines lines'),
      findsOneWidget,
    );
    expect(
      find.textContaining('$starterChars chars'),
      findsOneWidget,
    );
  });

  testWidgets('status bar updates after text changes', (tester) async {
    await pumpEditor(tester);

    const newText = 'label start:\n    "Hello"\n    return\n';
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      newText,
    );
    await tester.pump();

    final lines = '\n'.allMatches(newText).length + 1;
    expect(find.textContaining('$lines lines'), findsOneWidget);
    expect(find.textContaining('${newText.length} chars'), findsOneWidget);
  });

  // ---------------------------------------------------------------
  // Status chip transitions
  // ---------------------------------------------------------------

  testWidgets('status chip shows Running once the preview auto-starts', (
    tester,
  ) async {
    await pumpEditor(tester);

    // The preview is live from launch, and Run keeps it that way.
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('editor-run-button')));
    await tester.pump();

    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('status chip shows issue count after parse error', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n\t"bad tab"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('1 issue'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });

  // ---------------------------------------------------------------
  // New button
  // ---------------------------------------------------------------

  testWidgets('New button resets to starter template when not dirty', (
    tester,
  ) async {
    await pumpEditor(tester);

    // Change text to something else so we can verify reset.
    const replacement = 'label start:\n    "Changed"\n    return\n';
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      replacement,
    );
    await tester.pump();

    // Mark as not dirty by running (which doesn't set _dirty) then calling New.
    // Actually, typing sets dirty to true. Tap New and expect the dialog.
    await tester.tap(find.byKey(const ValueKey('editor-new-button')));
    await tester.pumpAndSettle();

    // The discard dialog should appear.
    expect(find.text('Discard changes?'), findsOneWidget);

    // Confirm discard.
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    // The editor should be back to the starter template.
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('editor-script-field')),
    );
    expect(field.controller?.text, starterTemplate);
  });

  testWidgets('New button discard dialog cancel preserves text', (
    tester,
  ) async {
    await pumpEditor(tester);

    const replacement = 'label start:\n    "Modified"\n    return\n';
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      replacement,
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('editor-new-button')));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);

    // Cancel the dialog.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The editor should still have the modified text.
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('editor-script-field')),
    );
    expect(field.controller?.text, replacement);
  });

  // ---------------------------------------------------------------
  // Narrow layout
  // ---------------------------------------------------------------

  testWidgets('narrow viewport renders segmented tabs instead of side-by-side',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RenFlyEditorApp(
        audioPlayback: const RenPyNoOpAudioPlayback(),
        loadBundledAssets: () async => const {},
      ),
    );
    await tester.pump();

    // SegmentedButton with Editor/Preview tabs should be present.
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);

    // The splitter should NOT be present in narrow layout.
    expect(find.byKey(const ValueKey('editor-splitter')), findsNothing);
  });

  // ---------------------------------------------------------------
  // Syntax highlighting: all token types
  // ---------------------------------------------------------------

  test('SyntaxHighlightController colors strings green', () {
    final controller = SyntaxHighlightController(text: '"hello world"');
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    final children = span.children!;
    expect(children, isNotEmpty);
    final stringSpan = children.firstWhere(
      (s) => (s as TextSpan).text == '"hello world"',
    ) as TextSpan;
    expect(stringSpan.style?.color, const Color(0xFF81C784));
  });

  test('SyntaxHighlightController colors comments grey', () {
    final controller = SyntaxHighlightController(text: '# a comment');
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    final children = span.children!;
    expect(children, isNotEmpty);
    final commentSpan = children.firstWhere(
      (s) => (s as TextSpan).text == '# a comment',
    ) as TextSpan;
    expect(commentSpan.style?.color, const Color(0xFF616161));
  });

  test('SyntaxHighlightController colors labels purple', () {
    final controller = SyntaxHighlightController(text: 'label start');
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    final children = span.children!;
    expect(children, isNotEmpty);
    final labelSpan = children.firstWhere(
      (s) => (s as TextSpan).text == 'label start',
    ) as TextSpan;
    expect(labelSpan.style?.color, const Color(0xFFBA68C8));
  });

  test('SyntaxHighlightController colors numbers cyan', () {
    final controller = SyntaxHighlightController(text: 'x = 42');
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    final children = span.children!;
    expect(children, isNotEmpty);
    final numberSpan = children.firstWhere(
      (s) => (s as TextSpan).text == '42',
    ) as TextSpan;
    expect(numberSpan.style?.color, const Color(0xFF4FC3F7));
  });

  test('SyntaxHighlightController returns empty span for empty text', () {
    final controller = SyntaxHighlightController(text: '');
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    expect(span.text, '');
    expect(span.children, isNull);
  });

  test('SyntaxHighlightController handles mixed content', () {
    final controller = SyntaxHighlightController(
      text: 'show bg # comment\n"hello" 42',
    );
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    final children = span.children!;
    // Should have multiple styled spans for different token types.
    final colors = children
        .map((s) => (s as TextSpan).style?.color)
        .whereType<Color>()
        .toSet();
    // At minimum: keyword (show), comment (# comment) — the comment swallows
    // the rest of the first line, so "hello" and 42 are on the next line.
    expect(colors.length, greaterThanOrEqualTo(2));
  });

  // ---------------------------------------------------------------
  // MigrationReportDialog with issues
  // ---------------------------------------------------------------

  testWidgets('MigrationReportDialog renders severity groups and issue rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const report = FlyMigrationReport([
      FlyMigrationIssue(
        severity: FlyMigrationSeverity.lossy,
        kind: 'roundtrip-divergence',
        message: 'Content was lost',
        filename: 'test.rpy',
        linenumber: 5,
        snippet: 'camera at topleft',
      ),
      FlyMigrationIssue(
        severity: FlyMigrationSeverity.warning,
        kind: 'parse-warning',
        message: 'Suspicious construct',
      ),
      FlyMigrationIssue(
        severity: FlyMigrationSeverity.info,
        kind: 'unstructured-statement',
        message: 'Preserved verbatim',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () => showMigrationReportDialog(
                  context,
                  report,
                  title: 'Test Issues',
                  confirmLabel: 'Save Anyway',
                  cancelLabel: 'Cancel',
                ),
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    // The headline should report the non-faithful result.
    expect(find.textContaining('NOT fully faithful'), findsOneWidget);
    expect(find.textContaining('1 lossy'), findsOneWidget);
    expect(find.textContaining('1 warning'), findsOneWidget);

    // Severity group headers.
    expect(find.text('Lossy'), findsOneWidget);
    expect(find.text('Warnings'), findsOneWidget);
    expect(find.text('Info (faithful, not structured)'), findsOneWidget);

    // Issue rows present.
    expect(find.byKey(const ValueKey('migration-issue-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('migration-issue-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('migration-issue-2')), findsOneWidget);

    // Issue content is visible.
    expect(find.text('Content was lost'), findsOneWidget);
    expect(find.textContaining('test.rpy'), findsOneWidget);
    expect(find.text('camera at topleft'), findsOneWidget);

    // Both actions present.
    expect(
      find.byKey(const ValueKey('migration-report-confirm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('migration-report-cancel')),
      findsOneWidget,
    );
  });

  testWidgets('MigrationReportDialog cancel button returns false', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    bool? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  dialogResult = await showMigrationReportDialog(
                    context,
                    const FlyMigrationReport([
                      FlyMigrationIssue(
                        severity: FlyMigrationSeverity.lossy,
                        kind: 'test',
                        message: 'test issue',
                      ),
                    ]),
                    title: 'Cancel Test',
                    confirmLabel: 'OK',
                    cancelLabel: 'Cancel',
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    // Tap cancel.
    await tester.tap(find.byKey(const ValueKey('migration-report-cancel')));
    await tester.pumpAndSettle();

    expect(dialogResult, isFalse);
  });

  // ---------------------------------------------------------------
  // Splitter drag
  // ---------------------------------------------------------------

  testWidgets('splitter drag adjusts the split ratio', (tester) async {
    await pumpEditor(tester);

    // Find the splitter and get the initial editor pane width.
    final splitter = find.byKey(const ValueKey('editor-splitter'));
    expect(splitter, findsOneWidget);

    // Measure the initial width of the editor pane (first child of the Row in
    // the wide body). We do this by checking the SizedBox that wraps the editor.
    SizedBox editorBox() {
      final row = tester.widget<Row>(
        find.ancestor(
          of: splitter,
          matching: find.byType(Row),
        ).first,
      );
      return row.children.first as SizedBox;
    }

    final initialWidth = editorBox().width!;

    // Drag the splitter to the right by 100px.
    await tester.drag(splitter, const Offset(100, 0));
    await tester.pump();

    final newWidth = editorBox().width!;
    expect(newWidth, greaterThan(initialWidth));
  });

  // ---------------------------------------------------------------
  // Session asset management
  // ---------------------------------------------------------------

  test('sessionAssetPathFor places files by extension kind', () {
    expect(sessionAssetPathFor('pic.png'), 'game/images/pic.png');
    expect(sessionAssetPathFor('Pic.JPG'), 'game/images/Pic.JPG');
    expect(sessionAssetPathFor('track.opus'), 'game/audio/track.opus');
    expect(sessionAssetPathFor('track.mp3'), 'game/audio/track.mp3');
    expect(sessionAssetPathFor('notes.txt'), 'game/notes.txt');
    expect(sessionAssetPathFor('noext'), 'game/noext');
  });

  testWidgets('Assets panel opens, adds picked files, removes, and the chip '
      'stays accurate', (tester) async {
    final picked = <PickedAssetFile>[
      (name: 'mypic.png', bytes: tinyPng),
      (name: 'theme.ogg', bytes: Uint8List.fromList([1, 2, 3])),
      (name: 'notes.txt', bytes: Uint8List.fromList([4, 5])),
    ];
    await pumpEditor(tester, pickAssets: () async => picked);

    // Chip starts at zero and the panel opens empty.
    expect(find.byKey(const ValueKey('editor-assets-chip')), findsOneWidget);
    expect(find.text('0 assets'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-assets-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-assets-panel')), findsOneWidget);
    expect(find.textContaining('No session assets yet'), findsOneWidget);
    // The how-to-reference hint states the resolver's conventions.
    expect(find.textContaining('game/images/sylvie.png'), findsOneWidget);

    // Add… lands files under their conventional game/ paths.
    await tester.tap(find.byKey(const ValueKey('editor-assets-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('game/images/mypic.png'), findsOneWidget);
    expect(find.text('game/audio/theme.ogg'), findsOneWidget);
    expect(find.text('game/notes.txt'), findsOneWidget);
    expect(find.text('3 assets'), findsOneWidget);

    // Per-asset Remove updates both the list and the chip.
    await tester.tap(
      find.byKey(const ValueKey('editor-asset-remove-game/notes.txt')),
    );
    await tester.pumpAndSettle();
    expect(find.text('game/notes.txt'), findsNothing);
    expect(find.text('2 assets'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-assets-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-assets-panel')), findsNothing);
  });

  testWidgets('an added image asset is resolved and rendered by the preview', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      pickAssets: () async => [(name: 'mypic.png', bytes: tinyPng)],
    );

    await tester.tap(find.byKey(const ValueKey('editor-assets-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-assets-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-assets-close-button')));
    await tester.pumpAndSettle();
    expect(find.text('1 asset'), findsOneWidget);

    // `scene mypic` resolves to game/images/mypic.png, which is byte-backed,
    // so the preview renders it through a MemoryImage.
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    scene mypic\n    "Asset preview line"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    await pumpUntil(
      tester,
      () => tester
          .widgetList<Image>(find.byType(Image))
          .any((image) => image.image is MemoryImage),
      description: 'a MemoryImage-backed preview image',
    );
  });

  // ---------------------------------------------------------------
  // Examples menu
  // ---------------------------------------------------------------

  testWidgets('Examples menu lists the starter story, The Question, and '
      'Sylvie & Sylvie', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('editor-examples-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('editor-example-starter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-example-the-question')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-example-sylvie-and-sylvie')),
      findsOneWidget,
    );
    expect(
      find.text('Sylvie & Sylvie (two-character demo)'),
      findsOneWidget,
    );
  });

  testWidgets('Examples menu loads The Question without parse errors', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('editor-examples-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-example-the-question')),
    );
    await tester.pump();

    // The script is loaded asynchronously from the bundled asset.
    final controller =
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('editor-script-field')),
            )
            .controller!;
    await pumpUntil(
      tester,
      () => controller.text.contains('sylvie'),
      description: 'The Question loaded into the editor',
    );

    // The open-path migration flow may surface an informational report.
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('migration-report-confirm'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    // Diagnostics: parsed with zero errors (status bar never says
    // "Parse error", and no red error rows exist).
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Parse error'), findsNothing);

    // Loading an example clears the session assets.
    expect(find.text('0 assets'), findsOneWidget);
  });

  testWidgets('Examples menu restores the starter story', (tester) async {
    await pumpEditor(tester);

    // Replace the script, then load the starter example over it (confirming
    // the discard prompt).
    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Changed"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-examples-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-example-starter')));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('editor-script-field')),
    );
    expect(field.controller?.text, starterTemplate);
  });

  testWidgets('bundled The Question asset parses with zero errors', (
    tester,
  ) async {
    // Real asset I/O must run outside the test's fake-async zone or it can
    // hang depending on what earlier tests left in the loader.
    // cache: false — an earlier test may have started this same load inside
    // its fake-async zone, leaving a never-completing future in the cache.
    final text = (await tester.runAsync(
      () => rootBundle.loadString(
        'assets/examples/the_question.rpy',
        cache: false,
      ),
    ))!;
    expect(text, contains('sylvie'));
    expect(text.startsWith('\uFEFF'), isFalse,
        reason: 'the bundled copy must not carry a UTF-8 BOM');

    final result = RenPyParser().parse(text, 'the_question.rpy');
    expect(result.warnings, isEmpty);
    expect(result.script.statements, isNotEmpty);
  });

  // ---------------------------------------------------------------
  // Bundled example art
  // ---------------------------------------------------------------

  test('bundledExampleAssetFiles covers the sprites, backgrounds, and music',
      () {
    expect(
      bundledExampleAssetFiles
          .where((path) => path.startsWith('game/images/sylvie '))
          .length,
      8,
    );
    expect(
      bundledExampleAssetFiles
          .where((path) => path.startsWith('game/images/bg '))
          .length,
      4,
    );
    expect(bundledExampleAssetFiles, contains('game/illurock.opus'));
  });

  testWidgets('bundled The Question art ships in the asset bundle', (
    tester,
  ) async {
    // Real asset I/O must run outside the test's fake-async zone or it can
    // hang (see the bundled-script test above). Every other test injects an
    // in-memory loader, so these keys are not poisoned in the cache.
    for (final path in bundledExampleAssetFiles) {
      final data = (await tester.runAsync(
        () => rootBundle.load('assets/examples/the_question/$path'),
      ))!;
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });

  testWidgets('bundled Sylvie & Sylvie asset parses with zero warnings', (
    tester,
  ) async {
    final text = (await tester.runAsync(
      () => rootBundle.loadString(
        'assets/examples/sylvie_and_sylvie.rpy',
        cache: false,
      ),
    ))!;
    expect(text, contains('Sylvie (green)'));
    expect(text.startsWith('\uFEFF'), isFalse,
        reason: 'the bundled copy must not carry a UTF-8 BOM');

    final result = RenPyParser().parse(text, 'sylvie_and_sylvie.rpy');
    expect(result.warnings, isEmpty);
    expect(result.script.statements, isNotEmpty);
  });

  testWidgets('bundled art preloads into the session at startup', (
    tester,
  ) async {
    await pumpEditor(tester, bundledAssets: fakeBundledAssets);
    await pumpUntil(
      tester,
      () => find.text(bundledAssetCount).evaluate().isNotEmpty,
      description: 'preloaded bundled art in the assets chip',
    );

    // The preloaded art is listed in the Assets panel under session paths.
    await tester.tap(find.byKey(const ValueKey('editor-assets-button')));
    await tester.pumpAndSettle();
    expect(find.text('game/illurock.opus'), findsOneWidget);
    expect(find.text('game/images/bg club.jpg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('editor-assets-close-button')));
    await tester.pumpAndSettle();
  });

  // ---------------------------------------------------------------
  // Character gallery
  // ---------------------------------------------------------------

  test('groupGalleryImages groups variants by tag and splits out backgrounds',
      () {
    final gallery = groupGalleryImages([
      'game/images/sylvie green smile.png',
      'game/images/sylvie blue normal.png',
      'game/images/bg meadow.jpg',
      'game/images/hero.png',
      'game/audio/theme.ogg',
      'game/illurock.opus',
      'game/images/nested/extra.png',
      'game/images/notes.txt',
    ]);

    expect(gallery.characters.keys.toSet(), {'sylvie', 'hero'});
    expect(
      gallery.characters['sylvie']!.map((image) => image.showName).toList(),
      ['sylvie blue normal', 'sylvie green smile'],
    );
    expect(gallery.characters['hero']!.single.showName, 'hero');
    expect(gallery.backgrounds.single.showName, 'bg meadow');
    expect(gallery.backgrounds.single.variant, 'meadow');
  });

  testWidgets('character gallery lists Sylvie variants and backgrounds from '
      'the preloaded art', (tester) async {
    await pumpEditor(tester, bundledAssets: fakeBundledAssets);
    await pumpUntil(
      tester,
      () => find.text(bundledAssetCount).evaluate().isNotEmpty,
      description: 'preloaded bundled art',
    );

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsOneWidget);

    // Section headers: the sprite tag and the backgrounds group.
    expect(find.text('sylvie'), findsOneWidget);
    expect(find.text('Backgrounds'), findsOneWidget);

    for (final variant in const [
      'blue giggle',
      'blue normal',
      'blue smile',
      'blue surprised',
      'green giggle',
      'green normal',
      'green smile',
      'green surprised',
    ]) {
      expect(
        find.byKey(ValueKey('editor-gallery-show-sylvie $variant')),
        findsOneWidget,
      );
      // Each variant offers at-left/center/right placement shortcuts.
      expect(
        find.byKey(ValueKey('editor-gallery-show-sylvie $variant-left')),
        findsOneWidget,
      );
    }
    for (final background in const ['club', 'lecturehall', 'meadow', 'uni']) {
      expect(
        find.byKey(ValueKey('editor-gallery-scene-bg $background')),
        findsOneWidget,
      );
    }

    // Thumbnails render the session bytes via Image.memory.
    final thumbnails = tester.widgetList<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('editor-gallery-panel')),
        matching: find.byType(Image),
      ),
    );
    expect(thumbnails.length, 12);
    expect(thumbnails.every((image) => image.image is MemoryImage), isTrue);

    await tester.tap(find.byKey(const ValueKey('editor-gallery-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsNothing);
  });

  testWidgets('tapping a gallery variant inserts a show statement at the '
      'cursor line', (tester) async {
    await pumpEditor(tester, bundledAssets: fakeBundledAssets);
    await pumpUntil(
      tester,
      () => find.text(bundledAssetCount).evaluate().isNotEmpty,
      description: 'preloaded bundled art',
    );

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n    "Beta"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller =
        tester
            .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
            .controller!;
    // Park the cursor in the "Alpha" line (line 2).
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-gallery-show-sylvie green smile')),
    );
    await tester.pumpAndSettle();

    // The dialog closed and the show landed on its own line under "Alpha",
    // indented to match the block.
    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsNothing);
    expect(
      controller.text,
      'label start:\n    "Alpha"\n    show sylvie green smile\n    "Beta"\n',
    );

    // The caret sits at the end of the inserted line, so a placement
    // shortcut stacks the next show right below it.
    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('editor-gallery-show-sylvie blue normal-right'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.text,
      'label start:\n    "Alpha"\n    show sylvie green smile\n'
      '    show sylvie blue normal at right\n    "Beta"\n',
    );
  });

  testWidgets('tapping a gallery background inserts a scene statement', (
    tester,
  ) async {
    await pumpEditor(tester, bundledAssets: fakeBundledAssets);
    await pumpUntil(
      tester,
      () => find.text(bundledAssetCount).evaluate().isNotEmpty,
      description: 'preloaded bundled art',
    );

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller =
        tester
            .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
            .controller!;
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();
    final meadow = find.byKey(const ValueKey('editor-gallery-scene-bg meadow'));
    await tester.ensureVisible(meadow);
    await tester.pumpAndSettle();
    await tester.tap(meadow);
    await tester.pumpAndSettle();

    expect(
      controller.text,
      'label start:\n    "Alpha"\n    scene bg meadow\n',
    );
  });

  testWidgets('two-character helper inserts paired shows at left and right', (
    tester,
  ) async {
    await pumpEditor(tester, bundledAssets: fakeBundledAssets);
    await pumpUntil(
      tester,
      () => find.text(bundledAssetCount).evaluate().isNotEmpty,
      description: 'preloaded bundled art',
    );

    await tester.enterText(
      find.byKey(const ValueKey('editor-script-field')),
      'label start:\n    "Alpha"\n',
    );
    await tester.pump(const Duration(milliseconds: 500));
    final controller =
        tester
            .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
            .controller!;
    controller.selection = const TextSelection.collapsed(offset: 17);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const ValueKey('editor-gallery-button')));
    await tester.pumpAndSettle();

    // Pick the left and right characters, then insert the pair.
    await tester.tap(find.byKey(const ValueKey('editor-gallery-pair-left')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(const ValueKey('editor-gallery-pair-left-sylvie green smile'))
          .last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-gallery-pair-right')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(const ValueKey('editor-gallery-pair-right-sylvie blue giggle'))
          .last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editor-gallery-pair-insert')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('editor-gallery-panel')), findsNothing);
    expect(
      controller.text,
      'label start:\n    "Alpha"\n    show sylvie green smile at left\n'
      '    show sylvie blue giggle at right\n',
    );
  });

  testWidgets('Sylvie & Sylvie example loads, parses clean, and previews '
      'with sprites', (tester) async {
    await pumpEditor(tester, bundledAssets: fakeBundledAssets);
    await pumpUntil(
      tester,
      () => find.text(bundledAssetCount).evaluate().isNotEmpty,
      description: 'preloaded bundled art',
    );

    await tester.tap(find.byKey(const ValueKey('editor-examples-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-example-sylvie-and-sylvie')),
    );
    await tester.pump();

    // The script is loaded asynchronously from the bundled asset.
    final controller =
        tester
            .widget<TextField>(find.byKey(const ValueKey('editor-script-field')))
            .controller!;
    await pumpUntil(
      tester,
      () => controller.text.contains('Sylvie (green)'),
      description: 'Sylvie & Sylvie loaded into the editor',
    );

    // The open-path migration flow may surface an informational report.
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('migration-report-confirm'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    // Parsed clean: no errors and no warnings after the debounce.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Parse error'), findsNothing);
    expect(find.textContaining('warning'), findsNothing);

    // Loading an example keeps the bundled art in the session.
    expect(find.text(bundledAssetCount), findsOneWidget);

    // The preview auto-runs to the first dialogue line (the text also exists
    // in the editor's TextField, so wait for a second occurrence) ...
    await pumpUntil(
      tester,
      () =>
          find
              .textContaining('Hey! You look exactly like me.')
              .evaluate()
              .length >=
          2,
      attempts: 200,
      description: 'first Sylvie & Sylvie dialogue in the preview',
    );

    // ... with the meadow and both Sylvies resolved from session bytes.
    final spriteImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((image) => image.image is MemoryImage);
    expect(spriteImages.length, greaterThanOrEqualTo(3));
  });
}

class _FakeBuildContext extends Fake implements BuildContext {}
