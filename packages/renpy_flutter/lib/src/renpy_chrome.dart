import 'package:flutter/material.dart';
import 'package:renpy_core/renpy_core.dart'
    show RenPyGuiConfiguration, RenPyGuiFrameBackground, RenPyScreenSize;

import 'renpy_image_layer.dart';
import 'renpy_flutter_controller.dart';
import 'renpy_text.dart';

typedef RenPyDialogueImageResolver =
    RenPyDialogueResolvedImage Function(String assetPath);

/// An image resolved for Ren'Py chrome, with optional source dimensions.
final class RenPyDialogueResolvedImage {
  const RenPyDialogueResolvedImage({required this.provider, this.size});

  final ImageProvider<Object> provider;
  final Size? size;
}

/// Displays RenPy dialogue and errors over the current scene.
class RenPyDialogueView extends StatefulWidget {
  const RenPyDialogueView({
    super.key,
    required this.controller,
    this.dialogueStyle,
    this.screenSize,
    this.gui,
    this.imageProvider,
    this.imageResolver,
    this.textCps = 0,
  });

  final RenPyFlutterController controller;
  final TextStyle? dialogueStyle;
  final RenPyScreenSize? screenSize;
  final RenPyGuiConfiguration? gui;
  final RenPyImageProviderFactory? imageProvider;
  final RenPyDialogueImageResolver? imageResolver;

  /// Characters-per-second typewriter speed; zero reveals lines instantly.
  final double textCps;

  @override
  State<RenPyDialogueView> createState() => _RenPyDialogueViewState();
}

class _RenPyDialogueViewState extends State<RenPyDialogueView> {
  final RenPyTextRevealController _reveal = RenPyTextRevealController();

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// Completes the reveal first, then advances on the following input,
  /// mirroring standard visual novel behavior. Skip mode bypasses the reveal.
  void _advance() {
    if (!_reveal.isComplete && !widget.controller.skipEnabled) {
      _reveal.complete();
      return;
    }
    widget.controller.continueGame();
  }

  void _onRevealed() => widget.controller.notifyTextRevealed();

  /// Resolves `[var]` / `[obj.field]` references in plain dialogue against the
  /// store scope before the typewriter reveal and `{tag}` styling run. The
  /// controller's screen interpolation evaluates a single reference against the
  /// live store; an unresolved reference round-trips to its literal source so
  /// the bracketed text is preserved.
  String _interpolateDialogue(String text) {
    if (!text.contains('[')) return text;
    return RenPyTextInterpolation.apply(text, (expression) {
      final source = '[$expression]';
      final resolved = widget.controller.interpolateScreenText(source);
      return resolved == source ? null : resolved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final dialogueStyle = widget.dialogueStyle;
    final screenSize = widget.screenSize;
    final gui = widget.gui;
    final imageProvider = widget.imageProvider;
    final imageResolver = widget.imageResolver;
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is RenPyDialogue) {
          final theme = Theme.of(context);
          final who = status.character;
          final whoColor =
              _RenPyDialogueColor.parse(status.color) ?? Colors.white;
          final displayText = _interpolateDialogue(status.displayText);
          return LayoutBuilder(
            builder: (context, constraints) {
              final scaledDialogueStyle = _scaledDialogueStyle(
                dialogueStyle,
                gui,
                screenSize,
                constraints,
              );
              final baseDialogueStyle = theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
              );
              final effectiveDialogueStyle =
                  baseDialogueStyle?.merge(scaledDialogueStyle) ??
                  scaledDialogueStyle;
              final guiGeometry = _RenPyDialogueGeometry.fromGui(
                gui,
                screenSize,
                constraints,
                text: displayText,
                style: effectiveDialogueStyle,
                textDirection: Directionality.of(context),
              );
              if (guiGeometry != null) {
                return GestureDetector(
                  onTap: _advance,
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
                              image: _dialogueBoxImage(
                                gui,
                                imageResolver,
                                imageProvider,
                              ),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: _dialogueContent(
                              text: displayText,
                              who: who,
                              whoColor: whoColor,
                              theme: theme,
                              style: effectiveDialogueStyle,
                              textCps: widget.textCps,
                              revealController: _reveal,
                              onRevealed: _onRevealed,
                              padding: EdgeInsets.fromLTRB(
                                guiGeometry.dialogueLeft,
                                guiGeometry.dialogueTop,
                                guiGeometry.dialogueLeft,
                                guiGeometry.dialogueBottom,
                              ),
                              width: guiGeometry.dialogueWidth,
                              alignToBottom: guiGeometry.alignContentToBottom,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return GestureDetector(
                onTap: _advance,
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
                      clipBehavior: Clip.hardEdge,
                      child: _dialogueContent(
                        text: displayText,
                        who: who,
                        whoColor: whoColor,
                        theme: theme,
                        style: effectiveDialogueStyle,
                        textCps: widget.textCps,
                        revealController: _reveal,
                        onRevealed: _onRevealed,
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
  RenPyDialogueImageResolver? imageResolver,
  RenPyImageProviderFactory? imageProvider,
) {
  final background = gui?.textboxBackground;
  if (background == null) return null;

  final resolvedImage = _resolveDialogueImage(
    background.asset,
    imageResolver,
    imageProvider,
  );
  if (resolvedImage == null) return null;

  return DecorationImage(
    image: resolvedImage.provider,
    fit: BoxFit.fill,
    centerSlice: _centerSliceForBackground(background, resolvedImage.size),
  );
}

RenPyDialogueResolvedImage? _resolveDialogueImage(
  String assetPath,
  RenPyDialogueImageResolver? imageResolver,
  RenPyImageProviderFactory? imageProvider,
) {
  if (imageResolver != null) return imageResolver(assetPath);
  if (imageProvider == null) return null;
  return RenPyDialogueResolvedImage(provider: imageProvider(assetPath));
}

Rect? _centerSliceForBackground(Object background, Size? sourceSize) {
  if (background is! RenPyGuiFrameBackground || sourceSize == null) return null;

  final right = sourceSize.width - background.right;
  final bottom = sourceSize.height - background.bottom;
  if (background.left >= right || background.top >= bottom) return null;

  return Rect.fromLTRB(background.left, background.top, right, bottom);
}

Widget _dialogueContent({
  required String text,
  required String? who,
  required Color whoColor,
  required ThemeData theme,
  required TextStyle? style,
  required double textCps,
  required RenPyTextRevealController revealController,
  required VoidCallback onRevealed,
  EdgeInsets padding = EdgeInsets.zero,
  double? width,
  bool alignToBottom = false,
}) {
  final textColumn = Column(
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
      RenPyTextReveal(
        text,
        key: ValueKey('renpy-dialogue-text:$text'),
        cps: textCps,
        controller: revealController,
        onRevealed: onRevealed,
        style: style,
      ),
    ],
  );

  Widget content =
      width == null ? textColumn : SizedBox(width: width, child: textColumn);

  if (alignToBottom) {
    content = LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0.0;
        return SingleChildScrollView(
          reverse: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child:
                  width == null
                      ? textColumn
                      : SizedBox(width: width, child: textColumn),
            ),
          ),
        );
      },
    );
  } else {
    content = SingleChildScrollView(child: content);
  }

  return Padding(padding: padding, child: content);
}

final class _RenPyDialogueGeometry {
  const _RenPyDialogueGeometry({
    required this.top,
    required this.height,
    required this.dialogueLeft,
    required this.dialogueTop,
    required this.dialogueBottom,
    required this.alignContentToBottom,
    this.dialogueWidth,
  });

  final double top;
  final double height;
  final double dialogueLeft;
  final double dialogueTop;
  final double dialogueBottom;
  final bool alignContentToBottom;
  final double? dialogueWidth;

  static _RenPyDialogueGeometry? fromGui(
    RenPyGuiConfiguration? gui,
    RenPyScreenSize? screenSize,
    BoxConstraints constraints, {
    required String text,
    required TextStyle? style,
    required TextDirection textDirection,
  }) {
    final textboxHeight = gui?.textboxHeight ?? gui?.windowYMinimum;
    final size = screenSize;
    if (gui == null || textboxHeight == null || size == null) return null;
    if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
      return null;
    }

    final scale = _stageScale(size, constraints);
    if (scale == null) return null;
    final baseHeight = textboxHeight * scale;
    final yAlign = gui.textboxYAlign ?? gui.windowYAlign ?? 1.0;
    final dialogueX = gui.dialogueXPos ?? gui.windowXPadding ?? 0;
    final dialogueY = gui.dialogueYPos ?? gui.windowYPadding ?? 0;
    final dialogueLeft = dialogueX * scale;
    final dialogueTop = dialogueY * scale;
    final availableDialogueWidth = constraints.maxWidth - (dialogueLeft * 2);
    final dialogueWidth =
        availableDialogueWidth.isFinite && availableDialogueWidth > 0
            ? availableDialogueWidth
            : gui.dialogueWidth == null
            ? null
            : gui.dialogueWidth! * scale;
    final requiredHeight = _dialogueRequiredHeight(
      text: text,
      style: style,
      width: dialogueWidth,
      dialogueTop: dialogueTop,
      dialogueBottom: dialogueTop,
      textDirection: textDirection,
    );
    final expandedHeight =
        baseHeight < requiredHeight ? requiredHeight : baseHeight;
    final alignContentToBottom = expandedHeight > baseHeight + 0.5;
    final height =
        expandedHeight > constraints.maxHeight
            ? constraints.maxHeight
            : expandedHeight;
    final top = (constraints.maxHeight - height) * yAlign;
    return _RenPyDialogueGeometry(
      top: top,
      height: height,
      dialogueLeft: dialogueLeft,
      dialogueTop: dialogueTop,
      dialogueBottom: alignContentToBottom ? dialogueTop : 0,
      alignContentToBottom: alignContentToBottom,
      dialogueWidth: dialogueWidth,
    );
  }
}

double _dialogueRequiredHeight({
  required String text,
  required TextStyle? style,
  required double? width,
  required double dialogueTop,
  required double dialogueBottom,
  required TextDirection textDirection,
}) {
  if (style == null || width == null || text.isEmpty) return 0;

  return dialogueTop +
      dialogueBottom +
      _dialogueTextHeight(
        text: text,
        style: style,
        width: width,
        textDirection: textDirection,
      );
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
  RenPyGuiConfiguration? gui,
  RenPyScreenSize? screenSize,
  BoxConstraints constraints,
) {
  final fontSize = style?.fontSize;
  final size = screenSize;
  if (style == null || fontSize == null || size == null) return style;
  final scale = _stageScale(size, constraints);
  if (scale == null) return style;

  return style.copyWith(
    fontSize: _dialogueFontSizeForGui(fontSize, gui) * scale,
  );
}

double _dialogueTextHeight({
  required String text,
  required TextStyle style,
  required double width,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: RenPyTextSpanParser.parse(text, style: style),
    textDirection: textDirection,
    textScaler: TextScaler.noScaling,
  );
  try {
    painter.layout(maxWidth: width);
    return painter.height;
  } finally {
    painter.dispose();
  }
}

double _dialogueFontSizeForGui(double fontSize, RenPyGuiConfiguration? gui) {
  final textboxHeight = gui?.textboxHeight ?? gui?.windowYMinimum;
  if (textboxHeight == null) return fontSize;

  final dialogueTop = gui?.dialogueYPos ?? gui?.windowYPadding ?? 0;
  final availableHeight = textboxHeight - dialogueTop;
  if (!availableHeight.isFinite || availableHeight <= 0) return fontSize;

  // Leave room for two wrapped ADV dialogue lines and Flutter font leading.
  final cappedFontSize = availableHeight / 3.0;
  if (!cappedFontSize.isFinite || cappedFontSize <= 0) return fontSize;
  return fontSize < cappedFontSize ? fontSize : cappedFontSize;
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

/// Scrollable overlay listing the dialogue lines shown so far, oldest at the
/// top and newest at the bottom, mirroring a standard visual novel backlog.
class RenPyBacklogView extends StatefulWidget {
  const RenPyBacklogView({
    super.key,
    required this.controller,
    required this.onClose,
    this.dialogueStyle,
  });

  final RenPyFlutterController controller;
  final VoidCallback onClose;
  final TextStyle? dialogueStyle;

  @override
  State<RenPyBacklogView> createState() => _RenPyBacklogViewState();
}

class _RenPyBacklogViewState extends State<RenPyBacklogView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        theme.textTheme.bodyLarge?.copyWith(color: Colors.white) ??
        const TextStyle(color: Colors.white);
    final textStyle =
        widget.dialogueStyle == null
            ? baseStyle
            : baseStyle.merge(widget.dialogueStyle);
    return Positioned.fill(
      key: const ValueKey('renpy-backlog-view'),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.86),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    key: const ValueKey('renpy-backlog-close'),
                    tooltip: 'Close',
                    color: Colors.white,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<RenPyBacklogEntry>>(
                  valueListenable: widget.controller.dialogueHistoryListenable,
                  builder: (context, entries, _) {
                    if (entries.isEmpty) {
                      return Center(
                        child: Text('No dialogue yet.', style: baseStyle),
                      );
                    }
                    return ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: entries.length,
                      separatorBuilder:
                          (context, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _buildEntry(theme, textStyle, entries[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(
    ThemeData theme,
    TextStyle textStyle,
    RenPyBacklogEntry entry,
  ) {
    final who = entry.character;
    final whoColor = _RenPyDialogueColor.parse(entry.color) ?? Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (who != null && who.isNotEmpty) ...[
          Text(
            who,
            style: theme.textTheme.titleMedium?.copyWith(color: whoColor),
          ),
          const SizedBox(height: 4),
        ],
        RenPyText(entry.text, style: textStyle),
      ],
    );
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
