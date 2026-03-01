import 'package:flutter/material.dart';
import '../controller.dart';

/// Displays dialogue lines coming from [RenPyFlutterController].
class DialogueView extends StatelessWidget {
  const DialogueView({super.key, required this.controller});
  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is RenPyDialogue) {
          final who = status.character;
          return GestureDetector(
            onTap: controller.continueGame,
            behavior: HitTestBehavior.opaque,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 112),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (who != null) ...[
                        Text(
                          who,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                      ],
                      _RenPyText(
                        status.text,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (status is RenPyError) {
          return Center(child: Text('Error: ${status.message}'));
        }
        // Anything else -> render nothing (background stays visible).
        return const SizedBox.shrink();
      },
    );
  }
}

class _RenPyText extends StatelessWidget {
  const _RenPyText(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(style: style, children: _parseSpans()));
  }

  List<TextSpan> _parseSpans() {
    final spans = <TextSpan>[];
    var bold = false;
    var italic = false;
    var index = 0;

    for (final match in RegExp(r'\{[^}]+\}').allMatches(text)) {
      if (match.start > index) {
        spans.add(_span(text.substring(index, match.start), bold, italic));
      }

      switch (match.group(0)) {
        case '{b}':
          bold = true;
          break;
        case '{/b}':
          bold = false;
          break;
        case '{i}':
          italic = true;
          break;
        case '{/i}':
          italic = false;
          break;
      }
      index = match.end;
    }

    if (index < text.length) {
      spans.add(_span(text.substring(index), bold, italic));
    }

    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  TextSpan _span(String value, bool bold, bool italic) {
    return TextSpan(
      text: value,
      style: TextStyle(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
      ),
    );
  }
}
