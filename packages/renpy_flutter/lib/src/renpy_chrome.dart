import 'package:flutter/material.dart';

import 'renpy_flutter_controller.dart';
import 'renpy_text.dart';

/// Displays RenPy dialogue and errors over the current scene.
class RenPyDialogueView extends StatelessWidget {
  const RenPyDialogueView({super.key, required this.controller});

  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is RenPyDialogue) {
          final who = status.character;
          final whoColor =
              _RenPyDialogueColor.parse(status.color) ?? Colors.white;
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
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(color: whoColor),
                        ),
                        const SizedBox(height: 4),
                      ],
                      RenPyText(
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
        return const SizedBox.shrink();
      },
    );
  }
}

final class _RenPyDialogueColor {
  const _RenPyDialogueColor._();

  static Color? parse(String? expression) {
    if (expression == null) return null;

    final value = expression.trim();
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
      return null;
    }

    final argb = hex.length == 6 ? 'FF$hex' : hex;
    return Color(int.parse(argb, radix: 16));
  }
}

/// Overlay that shows RenPy in-game menus.
class RenPyMenuSelector extends StatelessWidget {
  const RenPyMenuSelector({super.key, required this.controller});

  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is! RenPyMenu) return const SizedBox.shrink();

        return Material(
          color: Colors.black54,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status.caption != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      status.caption!,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < status.choices.length; i += 1)
                      ElevatedButton(
                        key: ValueKey('menu_choice_$i'),
                        onPressed: () => status.onChoice(i),
                        child: Text(status.choices[i]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
