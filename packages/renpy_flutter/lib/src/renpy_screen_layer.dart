import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renpy_core/renpy_core.dart'
    show
        RenPyResolvedDisplayable,
        RenPyResolvedScreen,
        RenPyScreenAction,
        RenPyScreenActionKind,
        RenPyShownScreen;

import 'renpy_flutter_controller.dart';
import 'renpy_image_layer.dart';
import 'renpy_text.dart';

/// Renders the engine's shown screens as a widget layer above the game stage.
///
/// The layer resolves each [RenPyShownScreen] through the controller's runner
/// into a [RenPyResolvedScreen] tree and renders it. RenPy re-runs screen code
/// on every interaction, so the layer re-resolves whenever the runner reports a
/// screen-layer change and whenever the controller's status notifier fires, so
/// screens reflect live state. Button taps route back through
/// [RenPyFlutterController.executeScreenAction], which fires the change hook and
/// drives the next re-resolve.
class RenPyScreenLayer extends StatefulWidget {
  const RenPyScreenLayer({
    super.key,
    required this.controller,
    this.imageProvider,
  });

  final RenPyFlutterController controller;

  /// Resolves an image asset path to a provider for `add`/`imagebutton`. When
  /// null, [AssetImage] is used, matching the image layer's default.
  final RenPyImageProviderFactory? imageProvider;

  @override
  State<RenPyScreenLayer> createState() => _RenPyScreenLayerState();
}

class _RenPyScreenLayerState extends State<RenPyScreenLayer> {
  List<RenPyShownScreen> _shown = const [];

  /// Remembered scroll offsets for viewports/vpgrids, keyed by a stable id
  /// derived from the screen tag and the viewport's position in the tree. The
  /// layer re-resolves (and rebuilds the widget tree) on every interaction, so
  /// without this a scrolled viewport would snap back to the top each time.
  final Map<String, double> _scrollOffsets = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStatusChanged);
    widget.controller.onScreenLayerChanged = _onScreenLayerChanged;
    _shown = widget.controller.shownScreens;
  }

  @override
  void didUpdateWidget(RenPyScreenLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller
        ..removeListener(_onStatusChanged)
        ..onScreenLayerChanged = null;
      widget.controller
        ..addListener(_onStatusChanged)
        ..onScreenLayerChanged = _onScreenLayerChanged;
      _shown = widget.controller.shownScreens;
    }
  }

  void _onScreenLayerChanged(List<RenPyShownScreen> shown) {
    if (!mounted) return;
    setState(() => _shown = shown);
  }

  void _onStatusChanged() {
    if (!mounted) return;
    // The runner re-runs screen code each interaction; mirror that by syncing
    // the shown set and rebuilding so resolved trees reflect current state.
    setState(() => _shown = widget.controller.shownScreens);
  }

  void _runAction(RenPyScreenAction action) {
    widget.controller.executeScreenAction(action);
  }

  @override
  void dispose() {
    widget.controller
      ..removeListener(_onStatusChanged)
      ..onScreenLayerChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingCall = widget.controller.pendingCallScreen;
    if (_shown.isEmpty && pendingCall == null) {
      return const SizedBox.shrink();
    }

    final resolver = _RenPyScreenResolver(
      controller: widget.controller,
      imageProvider: widget.imageProvider ?? _defaultScreenImageProvider,
      onAction: _runAction,
      scrollOffsets: _scrollOffsets,
    );

    final layers = <Widget>[];
    for (final shown in _shown) {
      final resolved = widget.controller.resolveScreen(
        shown.name,
        positional: shown.positional,
        keywords: shown.keywords,
      );
      if (resolved == null) continue;
      layers.add(
        Positioned.fill(
          key: ValueKey('renpy-screen-${shown.tag}'),
          child: resolver.buildScreen(resolved, shown),
        ),
      );
    }

    // A `call screen` is modal: it dims and blocks the game beneath, draws the
    // screen content on top through the same displayable renderer, and on a
    // Return action the runner dismisses it and resumes execution.
    if (pendingCall != null) {
      final resolved = widget.controller.resolveScreen(
        pendingCall.name,
        positional: pendingCall.positional,
        keywords: pendingCall.keywords,
      );
      layers.add(
        Positioned.fill(
          key: ValueKey('renpy-call-screen-${pendingCall.tag}'),
          child: _modal(
            resolved == null
                ? const SizedBox.shrink()
                : resolver.buildScreen(resolved, pendingCall),
          ),
        ),
      );
    }

    if (layers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(fit: StackFit.expand, children: layers);
  }

  /// Wraps a call-screen's content in a modal barrier: a dim, opaque scrim
  /// blocks input to the game beneath while the content draws on top. The screen
  /// itself remains interactive, so a Return button still routes its action.
  Widget _modal(Widget content) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x99000000)),
        content,
      ],
    );
  }
}

ImageProvider<Object> _defaultScreenImageProvider(String assetPath) {
  return AssetImage(assetPath);
}

/// Walks a resolved screen tree, mapping each displayable `kind` to a widget
/// and applying its flattened style merged with property overrides.
class _RenPyScreenResolver {
  _RenPyScreenResolver({
    required this.controller,
    required this.imageProvider,
    required this.onAction,
    required this.scrollOffsets,
  });

  final RenPyFlutterController controller;
  final RenPyImageProviderFactory imageProvider;
  final void Function(RenPyScreenAction action) onAction;

  /// Persisted scroll offsets for viewports, keyed by `<screen tag>::<index>`.
  /// Owned by the layer state so a scroll position survives a re-resolve.
  final Map<String, double> scrollOffsets;

  /// The screen tag of the tree currently being built, used to key remembered
  /// viewport scroll positions, and a running count of viewports seen so each
  /// gets a stable, distinct key within a single screen.
  String _scrollTag = '';
  int _viewportIndex = 0;

  Widget buildScreen(RenPyResolvedScreen screen, RenPyShownScreen shown) {
    _scrollTag = shown.tag;
    _viewportIndex = 0;
    final children = _buildChildren(screen.children, shown);
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return Stack(fit: StackFit.expand, children: children);
  }

  List<Widget> _buildChildren(
    List<RenPyResolvedDisplayable> nodes,
    RenPyShownScreen shown,
  ) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      // `has <layout>` is a layout hint applied to the parent, not drawn.
      if (node.isHasLayout) continue;
      final widget = _build(node, shown);
      if (widget != null) widgets.add(widget);
    }
    return widgets;
  }

  Widget? _build(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    switch (node.kind) {
      case 'vbox':
        return _wrap(node, _buildBox(node, shown, Axis.vertical));
      case 'hbox':
        return _wrap(node, _buildBox(node, shown, Axis.horizontal));
      case 'fixed':
        return _wrap(node, _buildFixed(node, shown));
      case 'frame':
      case 'window':
        return _wrap(node, _buildFrame(node, shown));
      case 'grid':
        return _wrap(node, _buildGrid(node, shown));
      case 'vpgrid':
        return _wrap(node, _buildViewport(node, shown, grid: true));
      case 'side':
        return _wrap(node, _buildSide(node, shown));
      case 'viewport':
        return _wrap(node, _buildViewport(node, shown));
      case 'null':
        return _buildNull(node);
      case 'text':
      case 'label':
        return _wrap(node, _buildText(node, shown));
      case 'add':
      case 'image':
        return _wrap(node, _buildImage(node));
      case 'bar':
        return _wrap(node, _buildBar(node, Axis.horizontal));
      case 'vbar':
        return _wrap(node, _buildBar(node, Axis.vertical));
      case 'textbutton':
        return _wrap(node, _buildTextButton(node, shown));
      case 'imagebutton':
        return _wrap(node, _buildImageButton(node));
      case 'button':
        return _wrap(node, _buildButton(node, shown));
      case 'timer':
        return _buildTimer(node);
      case 'key':
        return _buildKey(node);
      case 'on':
        // Non-visual node; no displayable to draw.
        return null;
      default:
        // Unknown kind: render any children so nested content is not lost.
        final children = _buildChildren(node.children, shown);
        if (children.isEmpty) return null;
        return _wrap(node, Stack(children: children));
    }
  }

  // --- Containers -----------------------------------------------------------

  Widget _buildBox(
    RenPyResolvedDisplayable node,
    RenPyShownScreen shown,
    Axis axis,
  ) {
    final props = _merged(node);
    final children = _buildChildren(node.children, shown);
    final spacing = _toDouble(props['spacing']);
    final spaced =
        spacing == null || spacing <= 0 || children.isEmpty
            ? children
            : _withSpacing(children, spacing, axis);

    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: spaced,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced,
    );
  }

  List<Widget> _withSpacing(List<Widget> children, double spacing, Axis axis) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i += 1) {
      if (i > 0) {
        spaced.add(
          axis == Axis.vertical
              ? SizedBox(height: spacing)
              : SizedBox(width: spacing),
        );
      }
      spaced.add(children[i]);
    }
    return spaced;
  }

  Widget _buildFixed(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    final children = _buildChildren(node.children, shown);
    if (children.isEmpty) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [for (final child in children) _positionedInFixed(child)],
    );
  }

  Widget _positionedInFixed(Widget child) {
    // Children of a fixed keep their own alignment; wrap so an aligned child
    // can position itself within the stack.
    return Positioned.fill(child: child);
  }

  Widget _buildFrame(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    final props = _merged(node);
    final children = _buildChildren(node.children, shown);
    final padding = _resolvePadding(props);
    final body =
        children.isEmpty
            ? const SizedBox.shrink()
            : children.length == 1
            ? children.single
            : Column(mainAxisSize: MainAxisSize.min, children: children);

    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _colorOf(props['background']) ?? const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: body,
    );
  }

  Widget _buildGrid(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    final props = _merged(node);
    final children = _buildChildren(node.children, shown);
    if (children.isEmpty) return const SizedBox.shrink();

    final columns = _gridColumns(node, props, children.length);
    final spacing = _toDouble(props['spacing']) ?? 0;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      children: children,
    );
  }

  int _gridColumns(
    RenPyResolvedDisplayable node,
    Map<String, Object?> props,
    int count,
  ) {
    // `grid cols rows:` puts the column count in the first positional.
    if (node.positional.isNotEmpty) {
      final cols = _toInt(node.positional.first);
      if (cols != null && cols > 0) return cols;
    }
    final cols = _toInt(props['cols']);
    if (cols != null && cols > 0) return cols;
    return count < 1 ? 1 : count;
  }

  Widget _buildViewport(
    RenPyResolvedDisplayable node,
    RenPyShownScreen shown, {
    bool grid = false,
  }) {
    final props = _merged(node);
    final children = _buildChildren(node.children, shown);
    if (children.isEmpty) return const SizedBox.shrink();

    // `scrollbars` names which axes scroll: "horizontal"/"vertical"/"both".
    // A `vpgrid` defaults to vertical scrolling; a plain viewport to vertical
    // unless told otherwise.
    final scrollbars = props['scrollbars'];
    final horizontal =
        scrollbars == 'horizontal' ||
        scrollbars == 'both' ||
        (scrollbars == null && _toInt(props['xinitial']) != null);
    final vertical = scrollbars != 'horizontal';

    Widget content;
    if (grid) {
      content = _buildVpGrid(node, props, children);
    } else {
      content = Column(mainAxisSize: MainAxisSize.min, children: children);
    }

    // A distinct, stable key per viewport in this screen so its remembered
    // scroll offset is not confused with a sibling viewport's.
    final scrollKey = '$_scrollTag::${_viewportIndex++}';
    final showScrollbar = props['mousewheel'] != false;
    if (horizontal && vertical) {
      // The vertical axis is the primary one whose offset is persisted.
      final inner = _RenPyViewport(
        key: ValueKey('renpy-viewport-horizontal-$scrollKey'),
        viewportKey: const ValueKey('renpy-viewport-horizontal'),
        axis: Axis.horizontal,
        showScrollbar: false,
        offsets: scrollOffsets,
        offsetKey: '$scrollKey:h',
        child: content,
      );
      return _RenPyViewport(
        key: ValueKey('renpy-viewport-vertical-$scrollKey'),
        viewportKey: const ValueKey('renpy-viewport-vertical'),
        axis: Axis.vertical,
        showScrollbar: showScrollbar,
        offsets: scrollOffsets,
        offsetKey: '$scrollKey:v',
        child: inner,
      );
    }
    final axis = horizontal ? Axis.horizontal : Axis.vertical;
    return _RenPyViewport(
      key: ValueKey('renpy-viewport-$scrollKey'),
      viewportKey: ValueKey(
        horizontal ? 'renpy-viewport-horizontal' : 'renpy-viewport-vertical',
      ),
      axis: axis,
      showScrollbar: showScrollbar,
      offsets: scrollOffsets,
      offsetKey: '$scrollKey:${horizontal ? 'h' : 'v'}',
      child: content,
    );
  }

  Widget _buildVpGrid(
    RenPyResolvedDisplayable node,
    Map<String, Object?> props,
    List<Widget> children,
  ) {
    final cols = _toInt(props['cols']);
    final spacing = _toDouble(props['spacing']) ?? 0;
    if (cols != null && cols > 0) {
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        children: children,
      );
    }
    // No column count: lay the cells out in a single column.
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// RenPy `side` places its children into a 3x3 grid keyed by a positions
  /// string (e.g. `"c t b l r"`); positions consume children in declared
  /// order. 'c' is center, 't'/'b'/'l'/'r' the edges, and 'tl'/'tr'/'bl'/'br'
  /// the corners.
  ///
  /// The screen parser currently drops `side`'s positions string, so when no
  /// spec reaches the resolver each child is laid out in order around the box
  /// (center, then top, bottom, left, right, corners) rather than dropped.
  Widget _buildSide(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    final children = _buildChildren(node.children, shown);
    if (children.isEmpty) return const SizedBox.shrink();

    var positions = _sidePositions(node);
    if (positions.length < children.length) {
      positions = _defaultSidePositions(children.length);
    }

    return Stack(
      key: const ValueKey('renpy-side'),
      fit: StackFit.passthrough,
      children: [
        for (var i = 0; i < children.length; i += 1)
          Align(
            alignment: _sideAlignment(
              i < positions.length ? positions[i] : 'c',
            ),
            child: children[i],
          ),
      ],
    );
  }

  Alignment _sideAlignment(String key) {
    switch (key) {
      case 't':
        return Alignment.topCenter;
      case 'b':
        return Alignment.bottomCenter;
      case 'l':
        return Alignment.centerLeft;
      case 'r':
        return Alignment.centerRight;
      case 'tl':
        return Alignment.topLeft;
      case 'tr':
        return Alignment.topRight;
      case 'bl':
        return Alignment.bottomLeft;
      case 'br':
        return Alignment.bottomRight;
      default:
        return Alignment.center;
    }
  }

  List<String> _sidePositions(RenPyResolvedDisplayable node) {
    final spec =
        (node.positional.isNotEmpty && node.positional.first is String)
            ? node.positional.first! as String
            : node.properties['positions'] as String?;
    if (spec != null && spec.trim().isNotEmpty) {
      return spec.trim().split(RegExp(r'\s+'));
    }
    return const [];
  }

  List<String> _defaultSidePositions(int count) {
    const order = ['c', 't', 'b', 'l', 'r', 'tl', 'tr', 'bl', 'br'];
    return [for (var i = 0; i < count; i += 1) order[i % order.length]];
  }

  Widget _buildNull(RenPyResolvedDisplayable node) {
    final props = _merged(node);
    return SizedBox(
      width: _toDouble(props['width']) ?? 0,
      height: _toDouble(props['height']) ?? 0,
    );
  }

  // --- Content --------------------------------------------------------------

  Widget _buildText(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    return _text(node, node.text ?? '', shown);
  }

  Widget _text(
    RenPyResolvedDisplayable node,
    String raw,
    RenPyShownScreen shown,
  ) {
    final props = _merged(node);
    return RenPyText(
      _interpolated(node, raw, shown),
      style: _textStyle(props),
      textAlign: _textAlign(props),
    );
  }

  /// The node's text with `[var]` references resolved. The resolver already
  /// substitutes against the live screen scope (parameters and `for`/`$`
  /// locals), so [RenPyResolvedDisplayable.interpolatedText] is preferred; the
  /// controller's store-scope interpolation is the fallback.
  String _interpolated(
    RenPyResolvedDisplayable node,
    String raw,
    RenPyShownScreen shown,
  ) {
    final resolved = node.interpolatedText;
    if (resolved != null) return resolved;
    return controller.interpolateScreenText(
      raw,
      screenName: shown.name,
      positional: shown.positional,
      keywords: shown.keywords,
    );
  }

  Widget _buildImage(RenPyResolvedDisplayable node) {
    final asset = _imageAsset(node);
    if (asset == null) return const SizedBox.shrink();
    return Image(
      image: imageProvider(asset),
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildBar(RenPyResolvedDisplayable node, Axis axis) {
    final props = _merged(node);
    final value = _toDouble(props['value']);
    final range = _toDouble(props['range']);
    final fraction =
        value != null && range != null && range > 0
            ? (value / range).clamp(0.0, 1.0)
            : null;

    // A bar is interactive when it carries an action, an adjustment, or a
    // `changed`/`released` callback; drag-end then routes through the action.
    final interactive =
        node.action != null ||
        props.containsKey('adjustment') ||
        props.containsKey('changed') ||
        props.containsKey('released');

    if (interactive && fraction != null) {
      // When the bar's action writes a variable/field (the common
      // `value VariableValue/FieldValue` pattern, expressed as an
      // `action SetVariable/SetField`), drag continuously rewrites the bound
      // value with the new absolute position (fraction * range) so the value
      // tracks the drag rather than only updating on release. Bars carrying a
      // non-writing action keep the on-release behavior.
      final writer = _barValueWriter(node.action, range);
      return _RenPyBarSlider(
        key: const ValueKey('renpy-bar'),
        axis: axis,
        value: fraction,
        onChanged: writer,
        onChangeEnd: node.action == null ? null : () => onAction(node.action!),
        length: _toDouble(props['xsize']) ?? _toDouble(props['ysize']) ?? 200,
      );
    }

    final indicator =
        axis == Axis.vertical
            ? RotatedBox(
              quarterTurns: 3,
              child: LinearProgressIndicator(value: fraction),
            )
            : LinearProgressIndicator(value: fraction);
    return SizedBox(
      key: const ValueKey('renpy-bar'),
      width: axis == Axis.horizontal ? _toDouble(props['xsize']) ?? 200 : null,
      height: axis == Axis.vertical ? _toDouble(props['ysize']) ?? 200 : null,
      child: indicator,
    );
  }

  /// Builds a drag callback that rewrites a bar's bound value as it moves, or
  /// null when the bar's action does not write a variable/field. The callback
  /// receives the new fraction (0..1) and writes `fraction * range` back through
  /// the same Set action, so the bound store/field tracks the drag continuously.
  void Function(double fraction)? _barValueWriter(
    RenPyScreenAction? action,
    double? range,
  ) {
    if (action == null || range == null) return null;
    switch (action.kind) {
      case RenPyScreenActionKind.setVariable:
      case RenPyScreenActionKind.setScreenVariable:
      case RenPyScreenActionKind.setField:
        return (fraction) {
          final scaled = fraction * range;
          // Keep integer ranges integral; the bound value is usually an int
          // count (e.g. a volume 0..100), not a fraction.
          final next = range == range.roundToDouble() ? scaled.round() : scaled;
          onAction(_withValue(action, next));
        };
      default:
        return null;
    }
  }

  /// Clones a Set-style [action] with its value replaced by [value], preserving
  /// the target/field so the runner writes the dragged amount.
  RenPyScreenAction _withValue(RenPyScreenAction action, Object? value) {
    return RenPyScreenAction(
      kind: action.kind,
      target: action.target,
      field: action.field,
      value: value,
      hasValue: true,
      screenName: action.screenName,
      label: action.label,
      functionName: action.functionName,
      positional: action.positional,
      keywords: action.keywords,
      raw: action.raw,
    );
  }

  // --- Buttons --------------------------------------------------------------

  Widget _buildTextButton(
    RenPyResolvedDisplayable node,
    RenPyShownScreen shown,
  ) {
    final props = _merged(node);
    return _button(
      node,
      child: RenPyText(
        _interpolated(node, node.text ?? '', shown),
        style: _textStyle(props),
        textAlign: _textAlign(props),
      ),
    );
  }

  Widget _buildImageButton(RenPyResolvedDisplayable node) {
    final props = _merged(node);
    final idle = _stringProp(props, 'idle') ?? _imageAsset(node);
    final hover = _stringProp(props, 'hover');
    final selected = props['selected'] == true;
    final selectedIdle = _stringProp(props, 'selected_idle');
    final selectedHover = _stringProp(props, 'selected_hover');
    final insensitive = _stringProp(props, 'insensitive');
    final enabled = node.action != null && props['sensitive'] != false;

    Widget imageFor(String? asset) {
      if (asset == null) return const Icon(Icons.smart_button);
      return Image(
        image: imageProvider(asset),
        errorBuilder:
            (context, error, stackTrace) => const Icon(Icons.smart_button),
      );
    }

    final action = node.action;
    final alternate = node.alternateAction;
    return _RenPyImageButton(
      key: const ValueKey('renpy-imagebutton'),
      idle: imageFor(selected ? (selectedIdle ?? idle) : idle),
      hover: imageFor(
        selected
            ? (selectedHover ?? hover ?? selectedIdle ?? idle)
            : (hover ?? idle),
      ),
      insensitive: enabled ? null : imageFor(insensitive ?? idle),
      enabled: enabled,
      onTap: action == null ? null : () => onAction(action),
      onAlternate: alternate == null ? null : () => onAction(alternate),
    );
  }

  String? _stringProp(Map<String, Object?> props, String key) {
    final value = props[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  // --- Non-visual nodes -----------------------------------------------------

  /// `timer <delay> action <a> [repeat True]` fires its action after [delay]
  /// seconds. The widget owns the [Timer] and cancels it on dispose/rebuild.
  Widget? _buildTimer(RenPyResolvedDisplayable node) {
    final action = node.action;
    if (action == null) return null;
    final props = _merged(node);
    final delay =
        _toDouble(props['delay']) ??
        (node.positional.isNotEmpty ? _toDouble(node.positional.first) : null);
    if (delay == null || delay <= 0) return null;
    final repeat = props['repeat'] == true;
    return _RenPyScreenTimer(
      key: ValueKey('renpy-timer-${node.hashCode}'),
      delay: Duration(microseconds: (delay * 1000000).round()),
      repeat: repeat,
      onFire: () => onAction(action),
    );
  }

  /// `key "binding" action <a>` runs its action when the bound key is pressed
  /// while the screen has focus.
  Widget? _buildKey(RenPyResolvedDisplayable node) {
    final action = node.action;
    if (action == null) return null;
    final binding =
        node.positional.isNotEmpty && node.positional.first is String
            ? node.positional.first! as String
            : node.properties['key'] as String?;
    final key = _logicalKeyFor(binding);
    if (key == null) return null;
    return _RenPyScreenKey(
      key: ValueKey('renpy-key-$binding'),
      logicalKey: key,
      onActivate: () => onAction(action),
    );
  }

  LogicalKeyboardKey? _logicalKeyFor(String? binding) {
    if (binding == null) return null;
    switch (binding) {
      case 'K_RETURN':
      case 'input_enter':
        return LogicalKeyboardKey.enter;
      case 'K_ESCAPE':
      case 'game_menu':
        return LogicalKeyboardKey.escape;
      case 'K_SPACE':
      case 'dismiss':
        return LogicalKeyboardKey.space;
      case 'K_LEFT':
      case 'rollback':
        return LogicalKeyboardKey.arrowLeft;
      case 'K_RIGHT':
      case 'rollforward':
        return LogicalKeyboardKey.arrowRight;
      case 'K_UP':
        return LogicalKeyboardKey.arrowUp;
      case 'K_DOWN':
        return LogicalKeyboardKey.arrowDown;
      default:
        if (binding.length == 1) {
          return LogicalKeyboardKey(binding.toLowerCase().codeUnitAt(0));
        }
        return null;
    }
  }

  Widget _buildButton(RenPyResolvedDisplayable node, RenPyShownScreen shown) {
    final children = _buildChildren(node.children, shown);
    final child =
        children.isEmpty
            ? const SizedBox.shrink()
            : children.length == 1
            ? children.single
            : Column(mainAxisSize: MainAxisSize.min, children: children);
    return _button(node, child: child);
  }

  Widget _button(RenPyResolvedDisplayable node, {required Widget child}) {
    final action = node.action;
    final alternate = node.alternateAction;
    final onTap = action == null ? null : () => onAction(action);
    final onAlternate = alternate == null ? null : () => onAction(alternate);

    return GestureDetector(
      onSecondaryTap: onAlternate,
      onLongPress: onAlternate,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      ),
    );
  }

  // --- Property / style application -----------------------------------------

  /// Flattened style merged with property overrides (properties win).
  Map<String, Object?> _merged(RenPyResolvedDisplayable node) {
    if (node.style.isEmpty) return node.properties;
    return <String, Object?>{...node.style, ...node.properties};
  }

  /// Wraps [child] in alignment, sizing, and padding from the node's resolved
  /// style+properties. Layout containers handle their own children, so this
  /// only applies the outer positioning/box adjustments.
  Widget _wrap(RenPyResolvedDisplayable node, Widget child) {
    final props = _merged(node);
    var result = child;

    final maxWidth = _toDouble(props['xmaximum']);
    final maxHeight = _toDouble(props['ymaximum']);
    final width = _sizeOf(props, 'xsize');
    final height = _sizeOf(props, 'ysize');
    if (maxWidth != null || maxHeight != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? double.infinity,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: result,
      );
    }
    if (width != null || height != null) {
      result = SizedBox(width: width, height: height, child: result);
    }

    final padding = _resolvePadding(props);
    if (padding != null) {
      result = Padding(padding: padding, child: result);
    }

    final alignment = _alignmentOf(props);
    if (alignment != null) {
      result = Align(alignment: alignment, child: result);
    } else if (_isFill(props['xfill']) || _isFill(props['yfill'])) {
      result = SizedBox(
        width: _isFill(props['xfill']) ? double.infinity : null,
        height: _isFill(props['yfill']) ? double.infinity : null,
        child: result,
      );
    }

    return result;
  }

  Alignment? _alignmentOf(Map<String, Object?> props) {
    final align = props['align'];
    if (align is List && align.length == 2) {
      final x = _toDouble(align[0]);
      final y = _toDouble(align[1]);
      if (x != null && y != null) return _alignment(x, y);
    }

    final pos = props['pos'];
    var x = _toDouble(props['xalign']) ?? _alignFromPos(props['xpos']);
    var y = _toDouble(props['yalign']) ?? _alignFromPos(props['ypos']);
    if (pos is List && pos.length == 2) {
      x ??= _alignFromPos(pos[0]);
      y ??= _alignFromPos(pos[1]);
    }
    if (x == null && y == null) return null;
    return _alignment(x ?? 0.0, y ?? 0.0);
  }

  double? _alignFromPos(Object? value) {
    // A fractional pos (0.0-1.0) maps directly to an alignment fraction; an
    // absolute pixel pos has no fraction we can honor here, so it is ignored.
    final d = _toDouble(value);
    if (d == null) return null;
    if (d >= 0 && d <= 1) return d;
    return null;
  }

  Alignment _alignment(double x, double y) {
    return Alignment((x.clamp(0.0, 1.0) * 2) - 1, (y.clamp(0.0, 1.0) * 2) - 1);
  }

  EdgeInsets? _resolvePadding(Map<String, Object?> props) {
    final all = _padTuple(props['padding']);
    if (all != null) return all;

    final x = _toDouble(props['xpadding']);
    final y = _toDouble(props['ypadding']);
    if (x == null && y == null) return null;
    return EdgeInsets.symmetric(horizontal: x ?? 0, vertical: y ?? 0);
  }

  EdgeInsets? _padTuple(Object? value) {
    if (value is num) return EdgeInsets.all(value.toDouble());
    if (value is List) {
      final parts = [for (final v in value) _toDouble(v) ?? 0];
      if (parts.length == 2) {
        return EdgeInsets.symmetric(horizontal: parts[0], vertical: parts[1]);
      }
      if (parts.length == 4) {
        return EdgeInsets.fromLTRB(parts[0], parts[1], parts[2], parts[3]);
      }
    }
    return null;
  }

  TextStyle _textStyle(Map<String, Object?> props) {
    final color = _colorOf(props['color']) ?? _colorOf(props['text_color']);
    final size = _toDouble(props['size']);
    final bold = props['bold'] == true;
    final italic = props['italic'] == true;
    return TextStyle(
      color: color ?? Colors.white,
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : null,
      fontStyle: italic ? FontStyle.italic : null,
    );
  }

  TextAlign? _textAlign(Map<String, Object?> props) {
    final align = props['text_align'];
    final value = _toDouble(align);
    if (value == null) {
      final xalign = _toDouble(props['xalign']);
      if (xalign == null) return null;
      return _textAlignFromFraction(xalign);
    }
    return _textAlignFromFraction(value);
  }

  TextAlign _textAlignFromFraction(double value) {
    if (value <= 0.0) return TextAlign.left;
    if (value >= 1.0) return TextAlign.right;
    return TextAlign.center;
  }

  double? _sizeOf(Map<String, Object?> props, String key) {
    final value = props[key];
    if (_isFill(value)) return double.infinity;
    return _toDouble(value);
  }

  bool _isFill(Object? value) => value == true;

  String? _imageAsset(RenPyResolvedDisplayable node) {
    final candidates = <Object?>[
      node.properties['image'],
      if (node.positional.isNotEmpty) node.positional.first,
      node.properties['idle'],
      node.properties['ground'],
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.isNotEmpty) return candidate;
    }
    return null;
  }

  Color? _colorOf(Object? value) {
    if (value is String) return _colorFromHex(value);
    if (value is int) return Color(value | 0xFF000000);
    return null;
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// A scrolling viewport that remembers its offset across re-resolves.
///
/// The screen layer rebuilds the whole widget tree on every interaction, so a
/// plain [SingleChildScrollView] would reset to the top each time. This seeds
/// its [ScrollController] from [offsets] (keyed by [offsetKey]) and writes the
/// live offset back as the user scrolls, so the position persists.
class _RenPyViewport extends StatefulWidget {
  const _RenPyViewport({
    super.key,
    required this.viewportKey,
    required this.axis,
    required this.showScrollbar,
    required this.offsets,
    required this.offsetKey,
    required this.child,
  });

  final Key viewportKey;
  final Axis axis;
  final bool showScrollbar;
  final Map<String, double> offsets;
  final String offsetKey;
  final Widget child;

  @override
  State<_RenPyViewport> createState() => _RenPyViewportState();
}

class _RenPyViewportState extends State<_RenPyViewport> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: widget.offsets[widget.offsetKey] ?? 0,
  );

  @override
  void dispose() {
    _remember();
    _controller.dispose();
    super.dispose();
  }

  void _remember() {
    if (_controller.hasClients) {
      widget.offsets[widget.offsetKey] = _controller.offset;
    }
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification.metrics.axis == widget.axis) _remember();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = SingleChildScrollView(
      key: widget.viewportKey,
      controller: _controller,
      scrollDirection: widget.axis,
      child: widget.child,
    );
    final listened = NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: scrollView,
    );
    return widget.showScrollbar
        ? Scrollbar(controller: _controller, child: listened)
        : listened;
  }
}

/// A draggable slider rendering a RenPy `bar`/`vbar`, firing [onChangeEnd] on
/// release so the bound action runs once the drag settles.
class _RenPyBarSlider extends StatefulWidget {
  const _RenPyBarSlider({
    super.key,
    required this.axis,
    required this.value,
    required this.length,
    this.onChanged,
    this.onChangeEnd,
  });

  final Axis axis;
  final double value;
  final double length;

  /// Fired continuously with the new fraction (0..1) as the slider is dragged,
  /// so a bound value can track the drag.
  final void Function(double fraction)? onChanged;
  final VoidCallback? onChangeEnd;

  @override
  State<_RenPyBarSlider> createState() => _RenPyBarSliderState();
}

class _RenPyBarSliderState extends State<_RenPyBarSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(_RenPyBarSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final slider = Slider(
      value: _value.clamp(0.0, 1.0),
      onChanged: (next) {
        setState(() => _value = next);
        widget.onChanged?.call(next);
      },
      onChangeEnd: (_) => widget.onChangeEnd?.call(),
    );
    if (widget.axis == Axis.vertical) {
      return SizedBox(
        height: widget.length,
        child: RotatedBox(quarterTurns: 3, child: slider),
      );
    }
    return SizedBox(width: widget.length, child: slider);
  }
}

/// A RenPy `imagebutton` that swaps its idle/hover/insensitive image on state.
class _RenPyImageButton extends StatefulWidget {
  const _RenPyImageButton({
    super.key,
    required this.idle,
    required this.hover,
    required this.enabled,
    this.insensitive,
    this.onTap,
    this.onAlternate,
  });

  final Widget idle;
  final Widget hover;
  final Widget? insensitive;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onAlternate;

  @override
  State<_RenPyImageButton> createState() => _RenPyImageButtonState();
}

class _RenPyImageButtonState extends State<_RenPyImageButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.insensitive ?? widget.idle;
    }
    final child = _hovered ? widget.hover : widget.idle;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTap: widget.onAlternate,
        onLongPress: widget.onAlternate,
        child: GestureDetector(onTap: widget.onTap, child: child),
      ),
    );
  }
}

/// Fires a screen `timer` action after a delay, cancelling on dispose/rebuild.
class _RenPyScreenTimer extends StatefulWidget {
  const _RenPyScreenTimer({
    super.key,
    required this.delay,
    required this.repeat,
    required this.onFire,
  });

  final Duration delay;
  final bool repeat;
  final VoidCallback onFire;

  @override
  State<_RenPyScreenTimer> createState() => _RenPyScreenTimerState();
}

class _RenPyScreenTimerState extends State<_RenPyScreenTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_RenPyScreenTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay != widget.delay || oldWidget.repeat != widget.repeat) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.repeat) {
      _timer = Timer.periodic(widget.delay, (_) => widget.onFire());
    } else {
      _timer = Timer(widget.delay, widget.onFire);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Binds a screen `key` action to a logical keyboard key.
///
/// The binding is registered on [HardwareKeyboard] rather than a focused
/// [Focus] node so it never steals focus from the player's input node. A normal
/// `show screen hud` carrying a `key` therefore does not break tapping or
/// spacebar-advancing the dialogue beneath it: the handler fires the action for
/// the bound key and always returns `false`, letting the same key event still
/// propagate to the game's focus-based dialogue advance. The handler exists only
/// while the screen carrying the `key` is shown, so the layer stays inert when
/// no screen is on the layer.
class _RenPyScreenKey extends StatefulWidget {
  const _RenPyScreenKey({
    super.key,
    required this.logicalKey,
    required this.onActivate,
  });

  final LogicalKeyboardKey logicalKey;
  final VoidCallback onActivate;

  @override
  State<_RenPyScreenKey> createState() => _RenPyScreenKeyState();
}

class _RenPyScreenKeyState extends State<_RenPyScreenKey> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != widget.logicalKey) return false;
    widget.onActivate();
    // Never mark the event handled: the bound action runs, but the same key is
    // still delivered to the game's focus node so dialogue advance is intact.
    return false;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Color? _colorFromHex(String expression) {
  final value = expression.trim();
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (!RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex) &&
      !RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
    return null;
  }
  final expanded =
      hex.length == 3 ? hex.split('').map((char) => '$char$char').join() : hex;
  final argb = expanded.length == 6 ? 'FF$expanded' : expanded;
  return Color(int.parse(argb, radix: 16));
}
