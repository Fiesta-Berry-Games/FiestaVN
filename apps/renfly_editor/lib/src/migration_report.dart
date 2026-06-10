import 'package:flutter/material.dart';
import 'package:renpy_writer/renpy_writer.dart';

/// Converts [rpySource] to a `.fly` document and merges in the round-trip
/// verification, so the caller sees every fidelity issue before saving.
///
/// This is the editor's save gate: a [FlyMigrationReport.isFaithful] result
/// means the produced `.fly` output reproduces an equivalent script, so the
/// save may proceed silently. Otherwise the report lists exactly which code
/// is not faithfully migrated.
///
/// Throws [RenPyParseError] (from `renpy_parser`) when [rpySource] does not
/// parse at all.
FlyMigrationResult runRpyToFlyGate(
  String rpySource, {
  String filename = 'editor.rpy',
}) {
  const migrator = FlyMigrator();
  final result = migrator.rpyToFly(rpySource, filename: filename);
  // rpyToFly already reports parse warnings and unstructured statements;
  // verifyRoundTrip repeats those, so only its divergence findings are new.
  final verification = migrator.verifyRoundTrip(rpySource, filename: filename);
  final divergences = [
    for (final issue in verification.issues)
      if (issue.kind == 'roundtrip-divergence') issue,
  ];
  if (divergences.isEmpty) return result;
  return FlyMigrationResult(
    result.output,
    FlyMigrationReport([...result.report.issues, ...divergences]),
  );
}

/// Shows a [MigrationReportDialog] for [report].
///
/// Returns `true` when the user pressed [confirmLabel], `false` when they
/// pressed [cancelLabel], and `null` when the dialog was dismissed. Pass
/// `cancelLabel: null` for a single-action (acknowledge-only) dialog.
Future<bool?> showMigrationReportDialog(
  BuildContext context,
  FlyMigrationReport report, {
  required String title,
  String confirmLabel = 'OK',
  String? cancelLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder:
        (context) => MigrationReportDialog(
          report: report,
          title: title,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
        ),
  );
}

/// Renders a [FlyMigrationReport]: a faithful/N-issues headline plus the
/// issue list grouped by severity (lossy, warning, info) with colored icons,
/// `kind` + message rows, `file:line` locations, and monospace snippets.
class MigrationReportDialog extends StatelessWidget {
  const MigrationReportDialog({
    super.key,
    required this.report,
    required this.title,
    this.confirmLabel = 'OK',
    this.cancelLabel,
  });

  /// The fidelity findings to render.
  final FlyMigrationReport report;

  /// Dialog title, e.g. `Save .fly` or `Opened story.fly`.
  final String title;

  /// Label of the confirming action (pops `true`).
  final String confirmLabel;

  /// Label of the cancelling action (pops `false`); `null` hides it.
  final String? cancelLabel;

  static const _severityOrder = [
    FlyMigrationSeverity.lossy,
    FlyMigrationSeverity.warning,
    FlyMigrationSeverity.info,
  ];

  static Color severityColor(FlyMigrationSeverity severity) {
    return switch (severity) {
      FlyMigrationSeverity.lossy => Colors.redAccent,
      FlyMigrationSeverity.warning => Colors.amber,
      FlyMigrationSeverity.info => Colors.blueGrey,
    };
  }

  static IconData severityIcon(FlyMigrationSeverity severity) {
    return switch (severity) {
      FlyMigrationSeverity.lossy => Icons.error_outline,
      FlyMigrationSeverity.warning => Icons.warning_amber_outlined,
      FlyMigrationSeverity.info => Icons.info_outline,
    };
  }

  static String _severityLabel(FlyMigrationSeverity severity) {
    return switch (severity) {
      FlyMigrationSeverity.lossy => 'Lossy',
      FlyMigrationSeverity.warning => 'Warnings',
      FlyMigrationSeverity.info => 'Info (faithful, not structured)',
    };
  }

  @override
  Widget build(BuildContext context) {
    final issues = report.issues;
    return AlertDialog(
      key: const ValueKey('migration-report-dialog'),
      title: Text(title),
      content: SizedBox(
        width: 560,
        height: issues.isEmpty ? null : 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeadline(context),
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              Expanded(child: _buildIssueList(context)),
            ],
          ],
        ),
      ),
      actions: [
        if (cancelLabel case final label?)
          TextButton(
            key: const ValueKey('migration-report-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(label),
          ),
        FilledButton(
          key: const ValueKey('migration-report-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }

  Widget _buildHeadline(BuildContext context) {
    final theme = Theme.of(context);
    if (report.isFaithful) {
      final note =
          report.infoCount == 0
              ? null
              : '${report.infoCount} construct(s) preserved verbatim but not '
                  'structured.';
      return Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note == null
                  ? 'Fully faithful migration ✓'
                  : 'Fully faithful migration ✓ — $note',
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      );
    }
    final parts = <String>[
      if (report.lossyCount > 0) '${report.lossyCount} lossy',
      if (report.warningCount > 0) '${report.warningCount} warning(s)',
      if (report.infoCount > 0) '${report.infoCount} info',
    ];
    final count = report.issues.length;
    return Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Migration is NOT fully faithful: $count issue'
            '${count == 1 ? '' : 's'} (${parts.join(', ')}).',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.redAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIssueList(BuildContext context) {
    final children = <Widget>[];
    var rowIndex = 0;
    for (final severity in _severityOrder) {
      final issues = [
        for (final issue in report.issues)
          if (issue.severity == severity) issue,
      ];
      if (issues.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            _severityLabel(severity),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: severityColor(severity),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
      for (final issue in issues) {
        children.add(
          KeyedSubtree(
            key: ValueKey('migration-issue-$rowIndex'),
            child: _IssueRow(issue: issue),
          ),
        );
        rowIndex += 1;
      }
    }
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: children,
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

  final FlyMigrationIssue issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = MigrationReportDialog.severityColor(issue.severity);
    final location =
        issue.filename == null
            ? null
            : '${issue.filename}'
                '${issue.linenumber == null ? '' : ':${issue.linenumber}'}';
    return Padding(
      key: const ValueKey('migration-issue-row'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            MigrationReportDialog.severityIcon(issue.severity),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      issue.kind,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (location != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          location,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(issue.message, style: theme.textTheme.bodySmall),
                if (issue.snippet case final snippet?) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      snippet,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Courier New', 'Courier'],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
