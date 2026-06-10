import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly_editor/main.dart';
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

Future<void> pumpEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const RenFlyEditorApp(audioPlayback: RenPyNoOpAudioPlayback()),
  );
  await tester.pump();
}

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
    const script = 'label start:\n    camera at topleft\n    "Hello"\n';
    final result = runRpyToFlyGate(script);
    // camera is an unstructured statement — should surface as info.
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
      const RenFlyEditorApp(audioPlayback: RenPyNoOpAudioPlayback()),
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
}

class _FakeBuildContext extends Fake implements BuildContext {}
