import 'package:flutter/material.dart';
import 'package:renpy_core/renpy_core.dart'
    show RenPyGuiConfiguration, RenPyScreenSize;

import 'renpy_image_layer.dart';
import 'renpy_flutter_controller.dart';
import 'renpy_text.dart';

/// Displays RenPy dialogue and errors over the current scene.
class RenPyDialogueView extends StatelessWidget {
  const RenPyDialogueView({
    super.key,
    required this.controller,
    this.dialogueStyle,
    this.screenSize,
    this.gui,
    this.imageProvider,
  });

  final RenPyFlutterController controller;
  final TextStyle? dialogueStyle;
  final RenPyScreenSize? screenSize;
  final RenPyGuiConfiguration? gui;
  final RenPyImageProviderFactory? imageProvider;

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
              final guiGeometry = _RenPyDialogueGeometry.fromGui(
                gui,
                screenSize,
                constraints,
              );
              if (guiGeometry != null) {
                return GestureDetector(
                  onTap: controller.continueGame,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox.expand(
                    child: Stack(
                      children: [
                        Positioned(
                          top: guiGeometry.top,
                          left: 0,
                          right: 0,
                          height: guiGeometry.height,
                          child: Container(
                            key: const ValueKey('renpy-dialogue-box'),
                            decoration: _dialogueBoxDecoration(
                              showBorder: false,
                              image: _dialogueBoxImage(gui, imageProvider),
                            ),
                            child: _dialogueContent(
                              text: status.displayText,
                              who: who,
                              whoColor: whoColor,
                              theme: theme,
                              style:
                                  baseDialogueStyle?.merge(
                                    scaledDialogueStyle,
                                  ) ??
                                  scaledDialogueStyle,
                              padding: EdgeInsets.only(
                                left: guiGeometry.dialogueLeft,
                                top: guiGeometry.dialogueTop,
                              ),
                              width: guiGeometry.dialogueWidth,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
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
                      key: const ValueKey('renpy-dialogue-box'),
                      decoration: _dialogueBoxDecoration(),
                      child: _dialogueContent(
                        text: status.displayText,
                        who: who,
                        whoColor: whoColor,
                        theme: theme,
                        style:
                            baseDialogueStyle?.merge(scaledDialogueStyle) ??
                            scaledDialogueStyle,
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

BoxDecoration _dialogueBoxDecoration({
  bool showBorder = true,
  DecorationImage? image,
}) {
  return BoxDecoration(
    color: Colors.black.withValues(alpha: 0.72),
    border:
        showBorder
            ? Border.all(color: Colors.white.withValues(alpha: 0.16))
            : null,
    image: image,
    borderRadius: BorderRadius.circular(8),
  );
}

DecorationImage? _dialogueBoxImage(
  RenPyGuiConfiguration? gui,
  RenPyImageProviderFactory? imageProvider,
) {
  final textboxAsset = gui?.textboxAsset;
  if (textboxAsset == null || imageProvider == null) return null;

  return DecorationImage(image: imageProvider(textboxAsset), fit: BoxFit.fill);
}

Widget _dialogueContent({
  required String text,
  required String? who,
  required Color whoColor,
  required ThemeData theme,
  required TextStyle? style,
  EdgeInsets padding = EdgeInsets.zero,
  double? width,
}) {
  final content = SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (who != null) ...[
          Text(
            who,
            style: theme.textTheme.titleMedium?.copyWith(color: whoColor),
          ),
          const SizedBox(height: 4),
        ],
        RenPyText(text, style: style),
      ],
    ),
  );

  return Padding(
    padding: padding,
    child: width == null ? content : SizedBox(width: width, child: content),
  );
}

final class _RenPyDialogueGeometry {
  const _RenPyDialogueGeometry({
    required this.top,
    required this.height,
    required this.dialogueLeft,
    required this.dialogueTop,
    this.dialogueWidth,
  });

  final double top;
  final double height;
  final double dialogueLeft;
  final double dialogueTop;
  final double? dialogueWidth;

  static _RenPyDialogueGeometry? fromGui(
    RenPyGuiConfiguration? gui,
    RenPyScreenSize? screenSize,
    BoxConstraints constraints,
  ) {
    final textboxHeight = gui?.textboxHeight;
    final size = screenSize;
    if (gui == null || textboxHeight == null || size == null) return null;
    if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
      return null;
    }

    final scale = _stageScale(size, constraints);
    if (scale == null) return null;
    final height = textboxHeight * scale;
    final yAlign = gui.textboxYAlign ?? 1.0;
    final top = (constraints.maxHeight - height) * yAlign;
    return _RenPyDialogueGeometry(
      top: top,
      height: height,
      dialogueLeft: (gui.dialogueXPos ?? 0) * scale,
      dialogueTop: (gui.dialogueYPos ?? 0) * scale,
      dialogueWidth:
          gui.dialogueWidth == null ? null : gui.dialogueWidth! * scale,
    );
  }
}

double? _stageScale(RenPyScreenSize screenSize, BoxConstraints constraints) {
  final widthScale = constraints.maxWidth / screenSize.width;
  final heightScale = constraints.maxHeight / screenSize.height;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  if (!scale.isFinite || scale <= 0) return null;
  return scale;
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
  final scale = _stageScale(size, constraints);
  if (scale == null) return style;

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
