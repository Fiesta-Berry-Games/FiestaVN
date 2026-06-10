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

    // Before the first run the preview shows the placeholder.
    expect(
      find.byKey(const ValueKey('editor-preview-placeholder')),
      findsOneWidget,
    );
    expect(find.text('Idle'), findsOneWidget);
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
}

class _FakeBuildContext extends Fake implements BuildContext {}
