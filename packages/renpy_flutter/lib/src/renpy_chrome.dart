import 'package:flutter/material.dart';
import 'package:renpy_core/renpy_core.dart' show RenPyScreenSize;

import 'renpy_flutter_controller.dart';
import 'renpy_text.dart';

/// Displays RenPy dialogue and errors over the current scene.
class RenPyDialogueView extends StatelessWidget {
  const RenPyDialogueView({
    super.key,
    required this.controller,
    this.dialogueStyle,
    this.screenSize,
  });

  final RenPyFlutterController controller;
  final TextStyle? dialogueStyle;
  final RenPyScreenSize? screenSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is RenPyDialogue) {
          final theme = Theme.of(context);
          final who = status.character;
          final whoColor =
              _RenPyDialogueColor.parse(status.color) ?? Colors.white;
          return LayoutBuilder(
            builder: (context, constraints) {
              final scaledDialogueStyle = _scaledDialogueStyle(
                dialogueStyle,
                screenSize,
                constraints,
              );
              final baseDialogueStyle = theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
              );
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
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (who != null) ...[
                              Text(
                                who,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: whoColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            RenPyText(
                              status.displayText,
                              style:
                                  baseDialogueStyle?.merge(
                                    scaledDialogueStyle,
                                  ) ??
                                  scaledDialogueStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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

/// Scales RenPy script pixel sizes into the currently laid out stage.
TextStyle? _scaledDialogueStyle(
  TextStyle? style,
  RenPyScreenSize? screenSize,
  BoxConstraints constraints,
) {
  final fontSize = style?.fontSize;
  final size = screenSize;
  if (style == null || fontSize == null || size == null) return style;
  if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
    return style;
  }

  final widthScale = constraints.maxWidth / size.width;
  final heightScale = constraints.maxHeight / size.height;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  if (!scale.isFinite || scale <= 0) return style;

  return style.copyWith(fontSize: fontSize * scale);
}

/// Transparent tap target used while RenPy is waiting at a pause interaction.
class RenPyPauseView extends StatelessWidget {
  const RenPyPauseView({super.key, required this.controller});

  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is! RenPyPause) return const SizedBox.shrink();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.continueGame,
          child: const SizedBox.expand(),
        );
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
