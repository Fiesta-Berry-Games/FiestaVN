import 'dart:math' as math;

import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_arithmetic.dart';
import 'renpy_audio_event.dart';
import 'renpy_diagnostic.dart';
import 'renpy_dialogue_event.dart';
import 'renpy_expression_evaluator.dart';
import 'renpy_image_event.dart';
import 'renpy_image_placement.dart';
import 'renpy_layeredimage_resolver.dart';
import 'renpy_pause_event.dart';
import 'renpy_persistent_store.dart';
import 'renpy_python.dart';
import 'renpy_screen_action.dart';
import 'renpy_screen_runtime.dart';
import 'renpy_transition_event.dart';
import 'renpy_transition_intent.dart';
import 'renpy_transition_resolver.dart';
import 'renpy_runner_snapshot.dart';

enum _ExecutionContextKind { block, labelFallthrough, call, loop }

class _ExecutionContext {
  _ExecutionContext(
    this.block,
    this.position,
    this.kind, {
    this.callerLabel,
    this.loop,
  });

  final List<RenPyStatement> block;
  final int position; // where we should resume afterwards
  final _ExecutionContextKind kind;

  /// The label that was current when a call frame was pushed, restored on
  /// return so the public [RenPyRunner.currentLabel] reports the caller.
  final String? callerLabel;

  /// For a [_ExecutionContextKind.loop] frame, the loop statement to re-enter
  /// when the body block ends. [block]/[position] point at the loop statement
  /// itself so a `break` can resume after it.
  final RenPyStatement? loop;
}

/// Runtime iteration state for an executing top-level `for` loop, keyed by the
/// loop statement's identity. Holds the pending items so each pass binds the
/// next value before re-running the body.
class _ForLoopState {
  _ForLoopState(this.items);

  final List<Object?> items;
  int index = 0;
}

/// Resolves a jump/call target to its location in source order. A target is
/// either a `label` statement or a named `menu` (`menu name:`), both of which
/// RenPy treats as jump targets. [statement] is the resolved statement,
/// [parentBlock]/[index] its position, and [name] the target name.
class _LabelContext {
  const _LabelContext(this.statement, this.parentBlock, this.index, this.name);

  final RenPyStatement statement;
  final List<RenPyStatement> parentBlock;
  final int index;
  final String name;

  /// The block to descend into for a label target, or null for a named menu
  /// (whose own statement must run in place to present its choices).
  RenPyLabelStatement? get label =>
      statement is RenPyLabelStatement
          ? statement as RenPyLabelStatement
          : null;
}

/// Records where a nested block lives in source order: the block that owns it
/// (the parent block) and the index of the owning statement within that parent.
/// Used to resolve RenPy label fall-through - when a block ends, execution
/// continues with the statement that textually follows its owner, recursing up
/// the enclosing-block chain.
class _BlockOwner {
  const _BlockOwner(this.parentBlock, this.ownerIndex);

  final List<RenPyStatement> parentBlock;
  final int ownerIndex;
}

class _PendingDialogue {
  const _PendingDialogue(this.event, this.searchStart);

  final RenPyDialogueEvent event;
  final int searchStart;
}

/// A collected `init python:` block awaiting execution at load. [priority] is
/// the init priority (lower runs first), [sourceIndex] breaks priority ties in
/// source order, and [lines] are the block's top-level Python source lines.
class _InitPythonBlock {
  const _InitPythonBlock(this.priority, this.sourceIndex, this.lines);

  final int priority;
  final int sourceIndex;
  final List<String> lines;
}

class _InlineWaitTag {
  const _InlineWaitTag({required this.end, this.duration});

  final int end;
  final double? duration;
}

class _AudioChannelRegistration {
  const _AudioChannelRegistration({required this.mixer, this.loop});

  final String mixer;
  final bool? loop;
}

class _AudioChannelRegistrationCall {
  const _AudioChannelRegistrationCall({
    required this.name,
    required this.mixer,
    this.loop,
  });

  final String name;
  final String mixer;
  final bool? loop;
}

class _PythonAssignment {
  const _PythonAssignment(this.name, this.expression);

  final String name;
  final String expression;
}

class _PythonAugmentedAssignment {
  const _PythonAugmentedAssignment(this.name, this.operator, this.expression);

  final String name;
  final String operator;
  final String expression;
}

class _PythonCallArguments {
  const _PythonCallArguments({
    required this.positional,
    required this.keywords,
  });

  final List<String> positional;
  final Map<String, String> keywords;
}

class _AudioPlayExpression {
  const _AudioPlayExpression({
    required this.asset,
    this.fadein,
    this.fadeout,
    this.volume,
    this.ifChanged,
    this.loop,
  });

  final String asset;
  final String? fadein;
  final String? fadeout;
  final String? volume;
  final bool? ifChanged;
  final bool? loop;
}

class _AudioExpressionParts {
  const _AudioExpressionParts({
    required this.assetExpression,
    required this.modifiers,
  });

  final String assetExpression;
  final List<String> modifiers;
}

/// Execution state of a RenPy script
enum RenPyRunnerState {
  /// The script is ready to be executed
  ready,

  /// The script is currently executing
  running,

  /// The script is paused waiting for user input
  waitingForInput,

  /// The script has reached the end
  complete,

  /// An error occurred during execution
  error,
}

/// Callback for dialogue events
typedef DialogueCallback = void Function(String? character, String text);

/// Callback for structured dialogue events.
typedef DialogueEventCallback = void Function(RenPyDialogueEvent event);

/// Callback for menu events
typedef MenuCallback =
    void Function(
      List<String> choices,
      Function(int) onChoice,
      String? caption,
    );

/// Callback for image events
typedef ImageCallback =
    void Function(String? scene, String? show, String? hide);

/// Callback for structured image events.
typedef ImageEventCallback = void Function(RenPyImageEvent event);

/// Callback for image alias definitions.
typedef ImageDefinitionCallback =
    void Function(RenPyImageDefinitionEvent event);

/// Callback for audio events.
typedef AudioCallback = void Function(RenPyAudioEvent event);

/// Callback for visual transition events.
typedef TransitionCallback = void Function(RenPyTransitionEvent event);

/// Callback for RenPy pause events.
typedef PauseCallback = void Function(RenPyPauseEvent event);

/// A runner for executing RenPy scripts
class RenPyRunner {
  /// The parsed script
  final RenPyScript script;

  /// Stack for nested blocks, label fallthrough, and call return addresses.
  final List<_ExecutionContext> _stack = [];

  /// Maps each nested statement block (by identity) to its owner: the parent
  /// block and the index of the owning statement within it. Built once at load
  /// from the parsed script and used to implement label fall-through - when a
  /// block ends with an empty call stack, execution continues at the statement
  /// after its owner in source order, climbing this chain until a following
  /// statement exists (otherwise the script completes). Since `List` uses
  /// identity equality, an ordinary map keys safely by block instance.
  final Map<List<RenPyStatement>, _BlockOwner> _blockOwners = {};

  /// Per-`for`-statement iteration state, keyed by the statement's identity, so
  /// each loop pass binds the next item. Cleared when the loop exhausts.
  final Map<RenPyForStatement, _ForLoopState> _forLoopStates = Map.identity();

  /// Guard against a runaway top-level `while` whose condition never goes false
  /// (a script bug should not hang the app). Counts consecutive body passes per
  /// `while` statement and aborts with a diagnostic past the cap. Cleared when
  /// the loop exits normally.
  final Map<RenPyWhileStatement, int> _whileIterationCounts = Map.identity();

  static const int _maxScriptLoopIterations = 100000;

  /// The current state of the runner
  RenPyRunnerState _state = RenPyRunnerState.ready;
  RenPyRunnerState get state => _state;

  /// The current label being executed
  String? _currentLabel;
  String? get currentLabel => _currentLabel;

  /// The current position in the script
  int _position = 0;

  /// The current block of statements being executed
  List<RenPyStatement> _currentBlock = [];

  /// Variables defined in the script
  final Map<String, dynamic> _variables = {};

  /// Channels registered by Ren'Py audio init Python.
  final Map<String, _AudioChannelRegistration> _audioChannels = {};

  /// Deterministic source for the `renpy.random.*` shims. It is seeded from a
  /// fixed value (and re-seeded on [reset]) so a run - and every test - produces
  /// the same sequence of "random" results, which is what makes the shimmed
  /// `renpy.random.random/randint/choice` reproducible.
  math.Random _renpyRandom = math.Random(_renpyRandomSeed);

  static const int _renpyRandomSeed = 0x52656e50; // 'RenP'

  /// Ren'Py persistent namespace values assigned during this run.
  final Map<String, dynamic> _persistent;

  /// Ren'Py `config.` namespace values. Seeded from `define config.X` /
  /// `default config.X` and rebuilt on reset, just like the store.
  final Map<String, dynamic> _config = {};

  /// Ren'Py `gui.` namespace values. Seeded from `define gui.X` /
  /// `default gui.X` and rebuilt on reset, just like the store.
  final Map<String, dynamic> _gui = {};

  /// Optional backing store for persistent namespace values.
  final RenPyPersistentStore? _persistentStore;

  Map<String, dynamic> get persistent => Map.unmodifiable(_persistent);

  /// Character definitions
  final Map<String, Map<String, dynamic>> _characters = {};

  RenPyDialogueEvent? _lastDialogueEvent;
  _PendingDialogue? _pendingDialogue;

  /// A pending sprite revert from an `@`-say temporary-attribute swap: the image
  /// name to re-show once the swapped line is dismissed. Null when no swap is in
  /// flight.
  String? _pendingAttributeRevert;

  /// Whether a `voice` line is currently sounding on the dedicated voice
  /// channel. RenPy voice is one-shot: the next voice line or dialogue
  /// interrupts it. A `voice sustain` keeps it alive across the next line.
  bool _voiceActive = false;
  bool _voiceSustain = false;
  // True between a `voice` line and the dialogue line it belongs to, so that
  // first dialogue does not interrupt its own voice.
  bool _voiceJustStarted = false;
  late RenPyTransitionResolver _transitionResolver;
  final Map<String, RenPyImagePlacement> _transformPlacements = {};

  /// Parsed `transform` declarations, keyed by transform name. Holds the
  /// structured ATL node list so a renderer can drive the animation. The static
  /// placement in [_transformPlacements] remains the fallback for transforms
  /// with no animatable ATL.
  final Map<String, RenPyTransformStatement> _transforms = {};

  /// Parsed `screen` declarations, keyed by screen name. Collected during
  /// [_processDefines] and consumed by the screen runtime to resolve a shown
  /// screen on demand.
  final Map<String, RenPyScreenStatement> _screens = {};

  /// Registered `layeredimage` declarations, used to resolve a shown
  /// layeredimage into its ordered layer image names.
  RenPyLayeredImageRegistry _layeredImages = RenPyLayeredImageRegistry();

  /// The active attribute selection (group -> attribute) for each currently
  /// shown layeredimage, keyed by `layer::tag`. Lets an incremental
  /// `show eileen frown` update only the changed group while keeping the rest.
  final Map<String, Map<String, String>> _layeredImageAttributes = {};

  /// The currently-shown image name for each plain (non-layeredimage) sprite
  /// tag, keyed by tag. Updated on `show`/`scene`/`hide`. Used by the `@`-say
  /// temporary-attribute swap to detect a shown sprite, swap to the temporary
  /// attributes for one line, then revert.
  final Map<String, String> _shownImageNames = {};

  /// Parsed `style` declarations, keyed by style name, including their `is`
  /// parent links. Resolved through the parent chain by the screen runtime.
  final Map<String, RenPyStyle> _styles = {};

  /// The screens currently shown on the screen layer, in show order. Each entry
  /// records the screen name plus its (evaluated) invocation arguments so the
  /// renderer can re-resolve it against current state. A screen tag replaces a
  /// prior screen with the same tag/name.
  final List<RenPyShownScreen> _shownScreens = [];

  /// A pending `call screen`, when one is blocking for a [RenPyScreenAction]
  /// Return value. Null when no call screen is in flight.
  RenPyShownScreen? _callScreen;

  RenPyScreenRuntime? _screenRuntime;

  /// Notified whenever the set of shown screens changes (`show screen` /
  /// `hide screen` / a Show/Hide action), passing the current invocations so a
  /// controller can re-resolve and redraw the screen layer.
  void Function(List<RenPyShownScreen> shown)? onScreenLayerChanged;

  /// The screens currently on the screen layer, in show order.
  List<RenPyShownScreen> get shownScreens =>
      List<RenPyShownScreen>.unmodifiable(_shownScreens);

  /// The pending `call screen` request, or null when none is blocking.
  RenPyShownScreen? get pendingCallScreen => _callScreen;

  /// The screen runtime, lazily built over the collected screen/style
  /// registries and the runner's live Python scope. Resolves a screen into a
  /// platform-neutral [RenPyResolvedScreen] on demand.
  RenPyScreenRuntime get screenRuntime =>
      _screenRuntime ??= RenPyScreenRuntime(
        screens: _screens,
        styles: _styles,
        scope: _pythonScope,
      );

  /// Resolves the screen named [name] against current engine state. Returns
  /// null when no such screen is registered.
  RenPyResolvedScreen? resolveScreen(
    String name, {
    List<Object?> positional = const [],
    Map<String, Object?> keywords = const {},
  }) => screenRuntime.resolveScreen(
    name,
    positional: positional,
    keywords: keywords,
  );

  /// Substitutes RenPy `[expression]` references in [text] against current
  /// engine state, used by a renderer to fill a screen's raw text.
  ///
  /// When [screenName] is supplied, that screen's declared parameters are
  /// bound from [positional]/[keywords] first so a `[parameter]` resolves to
  /// the same value the screen body sees. Inline `{tags}` are left untouched.
  String interpolateScreenText(
    String text, {
    String? screenName,
    List<Object?> positional = const [],
    Map<String, Object?> keywords = const {},
  }) => screenRuntime.interpolate(
    text,
    screenName: screenName,
    positional: positional,
    keywords: keywords,
  );

  /// The Python-subset expression evaluator and the scope view that shares the
  /// runner's own `_variables`/`_persistent`/`_config`/`_gui` maps. Reads and
  /// in-place mutations (such as `list.append`) flow straight through to engine
  /// state, and the `config`/`gui` scopes are seeded from `define`/`default`
  /// (see [_processDefines]) so `config.X` / `gui.X` resolve consistently in
  /// conditions, `$` statements and `python:` blocks. The scope also carries a
  /// [RenPyApi] so `renpy.*` calls inside expressions reach the runner's shims.
  static const RenPyPythonEvaluator _pythonEvaluator = RenPyPythonEvaluator();
  static const RenPyPythonExecutor _pythonExecutor = RenPyPythonExecutor();
  late final RenPyMapScope _pythonScope = RenPyMapScope(
    store: _variables,
    persistent: _persistent,
    config: _config,
    gui: _gui,
    renpy: _RunnerRenPyApi(this),
  );

  /// The live Python evaluation scope, exposed so a renderer can resolve ATL
  /// property target expressions (e.g. `linear 1.0 xpos x`) against current
  /// engine state when compiling a transform's animation.
  RenPyPythonScope get pythonScope => _pythonScope;

  /// Callbacks for various events
  DialogueCallback? onDialogue;
  DialogueEventCallback? onDialogueEvent;
  MenuCallback? onMenu;
  ImageCallback? onImage;
  ImageEventCallback? onImageEvent;
  ImageDefinitionCallback? onImageDefinition;
  AudioCallback? onAudio;
  TransitionCallback? onTransition;
  PauseCallback? onPause;

  RenPyDiagnosticCallback? _onDiagnostic;

  /// Diagnostics emitted before [onDiagnostic] was wired (notably during
  /// construction, where `_processDefines` runs init-python blocks). They are
  /// flushed to the callback the moment one is assigned so a host that wires the
  /// callback after constructing the runner still observes load-time skips.
  final List<RenPyDiagnostic> _pendingDiagnostics = [];

  RenPyDiagnosticCallback? get onDiagnostic => _onDiagnostic;

  set onDiagnostic(RenPyDiagnosticCallback? callback) {
    _onDiagnostic = callback;
    if (callback != null && _pendingDiagnostics.isNotEmpty) {
      final pending = List<RenPyDiagnostic>.of(_pendingDiagnostics);
      _pendingDiagnostics.clear();
      for (final diagnostic in pending) {
        callback(diagnostic);
      }
    }
  }

  /// Invoked for `renpy.notify(message)`. When unset the call is a no-op.
  void Function(String message)? onNotify;

  /// Error message if an error occurred
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get isWaitingAtMenu =>
      _state == RenPyRunnerState.waitingForInput &&
      _pendingDialogue == null &&
      _position < _currentBlock.length &&
      _currentBlock[_position] is RenPyMenuStatement;

  RenPyRunner(this.script, {RenPyPersistentStore? persistentStore})
    : _persistentStore = persistentStore,
      _persistent = Map<String, dynamic>.of(
        persistentStore?.load() ?? const <String, dynamic>{},
      ) {
    // Initialize with the default block of statements
    _currentBlock = script.statements;
    _buildBlockOwners();
    _transitionResolver = RenPyTransitionResolver.fromScript(script);

    // Register layeredimage declarations so `show` can resolve their layers.
    _layeredImages = RenPyLayeredImageRegistry.fromScript(script);

    // Seed the standard mutable config collections so init-time
    // `config.X.append(...)` / `.update(...)` calls have a list/dict to act on.
    _seedConfigDefaults();

    // Process define statements to set up characters and variables
    _processDefines();
  }

  /// Standard Ren'Py `config.` attributes that ship as mutable collections.
  /// Games commonly extend these in `init python:` (e.g.
  /// `config.overlay_screens.append("quick_menu")`), so they must already exist
  /// as the right empty container or the append/update would skip. A `define
  /// config.X` / `default config.X` later overrides any of these.
  static const List<String> _configListDefaults = [
    'overlay_screens',
    'character_id_prefixes',
    'layers',
    'transient_layers',
    'context_clear_layers',
    'overlay_layers',
    'top_layers',
    'bottom_layers',
    'sticky_layers',
    'menu_clear_layers',
    'detached_layers',
    'python_callbacks',
    'start_callbacks',
    'interact_callbacks',
    'predict_callbacks',
    'periodic_callbacks',
    'label_callbacks',
    'translate_clean_stores',
    'searchpath',
    'keymap_overrides',
  ];

  static const List<String> _configDictDefaults = [
    'layer_clipping',
    'tag_layer',
    'adv_nvl_transition',
    'name_overrides',
  ];

  /// Seeds [_config] with the standard mutable Ren'Py config collections so
  /// `config.X.append(...)` / `config.X.update(...)` in `init python:` operate
  /// on a real container instead of skipping.
  void _seedConfigDefaults() {
    for (final name in _configListDefaults) {
      _config.putIfAbsent(name, () => <dynamic>[]);
    }
    for (final name in _configDictDefaults) {
      _config.putIfAbsent(name, () => <dynamic, dynamic>{});
    }
  }

  /// Process all init-time declarations in the script in RenPy's load order:
  ///
  ///  1. Register UI/transform metadata (transform/screen/style) and collect
  ///     the `init python:` blocks, ordered by init priority then source order.
  ///  2. Run every `init python:` body through the Python executor so the
  ///     classes/functions/variables they declare exist BEFORE any `define`/
  ///     `default` expression that depends on them is evaluated.
  ///  3. Evaluate `define` statements (init-time bindings).
  ///  4. Apply `default` statements LAST (game-start bindings), so
  ///     `default x = SomeClass()` constructs a real instance against a scope
  ///     that already has the class.
  ///
  /// Each init-python body is wrapped so a failure emits a skip diagnostic and
  /// load continues; an unsupported block never aborts construction.
  void _processDefines() {
    final defines = <RenPyDefineStatement>[];
    final defaults = <RenPyDefaultStatement>[];
    // Init-python blocks paired with their priority and a monotonically
    // increasing source index, so a stable sort orders them by priority first
    // and source order for ties (RenPy's init-block ordering).
    final initPythonBlocks = <_InitPythonBlock>[];
    var sourceIndex = 0;

    void collect(List<RenPyStatement> statements) {
      for (final statement in statements) {
        if (statement is RenPyDefineStatement) {
          defines.add(statement);
        } else if (statement is RenPyDefaultStatement) {
          defaults.add(statement);
        } else if (statement is RenPyPythonStatement) {
          // A standalone top-level python statement (not inside an `init`
          // block) keeps its prior load behavior: only audio-channel
          // registration is applied here. Its `init python:` counterpart is
          // gathered from the enclosing RenPyInitStatement below and fully
          // executed.
          _applyAudioChannelRegistration(statement.code);
        } else if (statement is RenPyTransformStatement) {
          _applyTransformStatement(statement);
        } else if (statement is RenPyScreenStatement) {
          _registerScreen(statement);
        } else if (statement is RenPyStyleStatement) {
          _registerStyle(statement);
        } else if (statement is RenPyInitStatement) {
          if (statement.isPython) {
            // The parser splits an `init python:` body into one
            // RenPyPythonStatement per top-level line; gather them back into a
            // single block so multi-line constructs (class/def/assignment runs)
            // execute together against the shared scope.
            final lines = <String>[
              for (final inner in statement.block)
                if (inner is RenPyPythonStatement) inner.code,
            ];
            initPythonBlocks.add(
              _InitPythonBlock(statement.priority, sourceIndex++, lines),
            );
          } else {
            collect(statement.block);
          }
        }
      }
    }

    collect(script.statements);

    // Stable sort by priority; ties keep source order via the recorded index.
    initPythonBlocks.sort((a, b) {
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) return byPriority;
      return a.sourceIndex.compareTo(b.sourceIndex);
    });

    for (final block in initPythonBlocks) {
      _runInitPythonBlock(block.lines);
    }

    for (final define in defines) {
      _applyDefinition(define.name, define.expression);
    }

    for (final aDefault in defaults) {
      _applyDefault(aDefault.name, aDefault.expression);
    }
  }

  /// Runs one collected `init python:` block. The parser hands the body as a
  /// single entry carrying the full indented source, so it is split into
  /// physical lines: every TOP-LEVEL (column-0) `renpy.music.register_channel`
  /// call is peeled off and registered here (the block executor does not model
  /// it), while the rest of the block - including any nested body - is joined
  /// and executed as a single Python block. Peeling is restricted to top-level
  /// lines so a `register_channel` inside a nested `def`/`if` body stays with
  /// the block rather than being lifted out and corrupting its structure. A
  /// failure emits a skip diagnostic and load continues - load never throws on
  /// an unsupported body.
  void _runInitPythonBlock(List<String> lines) {
    final executable = <String>[];
    for (final entry in lines) {
      for (final line in entry.split('\n')) {
        final isTopLevel = line.isNotEmpty && line[0] != ' ' && line[0] != '\t';
        if (isTopLevel && _applyAudioChannelRegistration(line)) continue;
        executable.add(line);
      }
    }
    if (executable.every((line) => line.trim().isEmpty)) return;

    final code = executable.join('\n');
    if (_tryExecutePythonBlock(code)) return;

    _emitDiagnostic(
      RenPyDiagnostic(
        code: RenPyDiagnosticCode.skippedPython,
        message: 'Skipped unsupported init Python block.',
        detail: code,
      ),
    );
  }

  /// Parse a character definition.
  void _parseCharacter(String name, String expression) {
    // This is a simplified parser for character definitions.

    final params = <String, dynamic>{};

    // Extract the character name (first parameter to Character()).
    final nameMatch = RegExp(
      r'''Character\s*\(\s*(?:_\(\s*)?["\']([^"\']*)["\']''',
    ).firstMatch(expression);
    if (nameMatch != null) {
      params['name'] = nameMatch.group(1);
    }

    // Extract other parameters like color.
    final colorMatch = RegExp(
      r'''color\s*=\s*["\']([^"\']*)["\']''',
    ).firstMatch(expression);
    if (colorMatch != null) {
      params['color'] = colorMatch.group(1);
    }

    // The `image=` keyword links a character to the sprite tag whose attributes
    // an `@`-say line temporarily swaps.
    final imageMatch = RegExp(
      r'''image\s*=\s*["\']([^"\']*)["\']''',
    ).firstMatch(expression);
    if (imageMatch != null) {
      params['image'] = imageMatch.group(1);
    }

    _characters[name] = params;
  }

  void _applyDefinition(String name, String expression) {
    if (expression.contains('Character(') ||
        expression.contains('Character (')) {
      _parseCharacter(name, expression);
    } else {
      _transitionResolver = _transitionResolver.withDefinition(
        name,
        expression,
      );
      // Namespaced targets (`config.X`, `gui.X`, `persistent.X`, ...) are
      // written into the matching scope rather than as a flat store key, so
      // `config.X` / `gui.X` reads resolve from defines. Bare names keep their
      // existing `_variables` storage so transitions and characters are
      // unchanged.
      if (_isNamespacedName(name)) {
        _pythonScope.write(name, _evaluateExpression(expression));
      } else {
        _variables[name] = _evaluateExpression(expression);
      }
    }
  }

  /// Applies a `default name = expression`, routing namespaced targets into the
  /// matching scope and bare names into the store. Mirrors RenPy's `default`:
  /// the value is only set when the name is not already present, so a value
  /// already supplied (for instance a surviving `persistent.X`) is preserved.
  void _applyDefault(String name, String expression) {
    if (_isNamespacedName(name)) {
      if (!_pythonScope.has(name)) {
        _pythonScope.write(name, _evaluateExpression(expression));
      }
      return;
    }
    _variables.putIfAbsent(name, () => _evaluateExpression(expression));
  }

  bool _isNamespacedName(String name) =>
      name.startsWith('persistent.') ||
      name.startsWith('config.') ||
      name.startsWith('gui.') ||
      name.startsWith('store.');

  void _applyTransformStatement(RenPyTransformStatement statement) {
    final name = _transformName(statement.signature);
    if (name == null) return;
    _transforms[name] = statement;
    final placement = _placementFromTransformBody(statement.body);
    if (placement != null) {
      _transformPlacements[name] = placement;
    }
  }

  /// The registered `transform` declarations, keyed by transform name. A
  /// renderer looks up the transform referenced by a `show X at name` clause
  /// (carried on the image event's `at`) to compile its ATL animation. The
  /// static placement remains available through the image event's `placement`.
  Map<String, RenPyTransformStatement> get transforms =>
      Map.unmodifiable(_transforms);

  /// The parsed ATL node list for the transform named [name], or null when no
  /// such transform is registered.
  List<RenPyAtlNode>? atlForTransform(String name) =>
      _transforms[name.trim()]?.atl;

  String? _transformName(String signature) {
    final match = RegExp(r'^([A-Za-z_]\w*)').firstMatch(signature.trim());
    return match?.group(1);
  }

  void _registerScreen(RenPyScreenStatement statement) {
    final name = _screenName(statement.signature);
    if (name == null) return;
    _screens[name] = statement;
  }

  void _registerStyle(RenPyStyleStatement statement) {
    final style = statement.style;
    if (style == null) return;
    _styles[style.name] = style;
  }

  /// The screen name from a `name(params)` signature.
  String? _screenName(String signature) {
    final match = RegExp(r'^([A-Za-z_]\w*)').firstMatch(signature.trim());
    return match?.group(1);
  }

  bool _isScreenDirective(String imageName) {
    final trimmed = imageName.trim();
    return trimmed == 'screen' || trimmed.startsWith('screen ');
  }

  String _stripScreenKeyword(String imageName) {
    final trimmed = imageName.trim();
    if (trimmed == 'screen') return '';
    return trimmed.substring('screen '.length).trim();
  }

  /// Adds a screen invocation to the screen layer and notifies listeners. A
  /// screen with the same name (its implicit tag) replaces a prior one.
  void _showScreen(String invocation) {
    final shown = _shownScreenFor(invocation);
    if (shown == null) return;
    _shownScreens.removeWhere((s) => s.tag == shown.tag);
    _shownScreens.add(shown);
    _notifyScreenLayerChanged();
  }

  /// Removes the screen with [name] (its tag) from the screen layer.
  void _hideScreen(String name) {
    final tag = _shownScreenFor(name)?.tag ?? name.trim();
    final before = _shownScreens.length;
    _shownScreens.removeWhere((s) => s.tag == tag);
    if (_shownScreens.length != before) {
      _notifyScreenLayerChanged();
    }
  }

  void _notifyScreenLayerChanged() {
    onScreenLayerChanged?.call(shownScreens);
  }

  /// Builds a [RenPyShownScreen] from a raw `name(args)` invocation, evaluating
  /// its argument expressions against the live store. Returns null when no name
  /// can be extracted.
  RenPyShownScreen? _shownScreenFor(String invocation) {
    final trimmed = invocation.trim();
    if (trimmed.isEmpty) return null;
    final open = trimmed.indexOf('(');
    if (open < 0) {
      return RenPyShownScreen(name: trimmed, tag: trimmed);
    }
    final close = trimmed.lastIndexOf(')');
    final name = trimmed.substring(0, open).trim();
    if (close <= open) {
      return RenPyShownScreen(name: name, tag: name);
    }
    final inner = trimmed.substring(open + 1, close);
    final parsed = _pythonCallArguments(inner);
    final positional = [
      for (final expression in parsed.positional)
        _evaluateExpression(expression),
    ];
    final keywords = <String, Object?>{
      for (final entry in parsed.keywords.entries)
        entry.key: _evaluateExpression(entry.value),
    };
    return RenPyShownScreen(
      name: name,
      tag: name,
      positional: positional,
      keywords: keywords,
    );
  }

  /// Performs a parsed screen [action] against engine state.
  ///
  /// Return/Jump/Call route into the existing runner control flow, Set/Toggle
  /// mutate the store through the Python scope, Show/Hide update the screen
  /// layer, and ShowMenu shows a screen by name. Anything not handled (a
  /// NullAction, or an action whose target could not be resolved) is a no-op.
  /// After a mutating action the runner reports the screen layer changed so the
  /// UI re-resolves screens against the new state.
  void executeScreenAction(RenPyScreenAction action) {
    switch (action.kind) {
      case RenPyScreenActionKind.returnValue:
        _resolveCallScreen(action.hasValue ? action.value : null);
      case RenPyScreenActionKind.jump:
        final label = action.label;
        if (label != null) jumpToLabel(label);
      case RenPyScreenActionKind.call:
        final label = action.label;
        if (label != null) _callLabelFromAction(label);
      case RenPyScreenActionKind.showScreen:
      case RenPyScreenActionKind.showMenu:
        final name = action.screenName;
        if (name != null) {
          _showScreen(
            _invocationText(name, action.positional, action.keywords),
          );
        }
      case RenPyScreenActionKind.hideScreen:
        final name = action.screenName;
        if (name != null) _hideScreen(name);
      case RenPyScreenActionKind.setVariable:
      case RenPyScreenActionKind.setScreenVariable:
        final name = action.target;
        if (name != null) {
          _setVariable(name, action.hasValue ? action.value : null);
          _notifyScreenLayerChanged();
        }
      case RenPyScreenActionKind.setField:
        _applySetField(action);
      case RenPyScreenActionKind.toggleVariable:
      case RenPyScreenActionKind.toggleScreenVariable:
        final name = action.target;
        if (name != null) {
          final current = _lookupVariable(name).value;
          _setVariable(name, !RenPyPythonEvaluator.truthy(current));
          _notifyScreenLayerChanged();
        }
      case RenPyScreenActionKind.toggleField:
        _applyToggleField(action);
      case RenPyScreenActionKind.addToSet:
        _applySetMembership(action, add: true);
      case RenPyScreenActionKind.removeFromSet:
        _applySetMembership(action, add: false);
      case RenPyScreenActionKind.function:
        _applyFunctionAction(action);
      case RenPyScreenActionKind.multiple:
        // Execute each sub-action in order. Order matters so that e.g.
        // `[Hide("foo"), Return()]` hides the screen before resolving the
        // pending call screen via the Return path.
        for (final sub in action.actions) {
          executeScreenAction(sub);
        }
      case RenPyScreenActionKind.nullAction:
        break;
    }
  }

  String _invocationText(
    String name,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    if (positional.isEmpty && keywords.isEmpty) return name;
    final args = <String>[
      for (final value in positional) _literalForArg(value),
      for (final entry in keywords.entries)
        '${entry.key}=${_literalForArg(entry.value)}',
    ];
    return '$name(${args.join(', ')})';
  }

  String _literalForArg(Object? value) {
    if (value is String) return "'$value'";
    return '$value';
  }

  /// Routes a Call action label into the call-stack machinery so the called
  /// label returns to where the player was. The screen layer is left intact.
  void _callLabelFromAction(String label) {
    final context = _findLabelContext(label);
    if (context == null) return;
    _stack.add(
      _ExecutionContext(
        _currentBlock,
        _position,
        _ExecutionContextKind.call,
        callerLabel: _currentLabel,
      ),
    );
    _enterLabelTarget(context);
    _state = RenPyRunnerState.running;
    _executeNext();
  }

  /// Resolves a pending `call screen` with [value]: hides the call screen,
  /// stores the result in `_return`, and resumes execution. With no call screen
  /// in flight this is a no-op (a bare `Return` outside a call screen).
  void _resolveCallScreen(Object? value) {
    final call = _callScreen;
    if (call == null) return;
    _callScreen = null;
    _shownScreens.removeWhere((s) => s.tag == call.tag);
    _setVariable('_return', value);
    _notifyScreenLayerChanged();
    if (_state == RenPyRunnerState.waitingForInput) {
      _state = RenPyRunnerState.running;
      _executeNext();
    }
  }

  void _applySetField(RenPyScreenAction action) {
    final object = action.target;
    final field = action.field;
    if (object == null || field == null) return;
    final value = action.hasValue ? action.value : null;
    final receiver = _evaluateExpression(object);
    if (receiver is Map) {
      receiver[field] = value;
      _notifyScreenLayerChanged();
    }
  }

  void _applyToggleField(RenPyScreenAction action) {
    final object = action.target;
    final field = action.field;
    if (object == null || field == null) return;
    final receiver = _evaluateExpression(object);
    if (receiver is Map) {
      receiver[field] = !RenPyPythonEvaluator.truthy(receiver[field]);
      _notifyScreenLayerChanged();
    }
  }

  void _applySetMembership(RenPyScreenAction action, {required bool add}) {
    final target = action.target;
    if (target == null || !action.hasValue) return;
    final collection = _evaluateExpression(target);
    if (collection is Set) {
      if (add) {
        collection.add(action.value);
      } else {
        collection.remove(action.value);
      }
      _notifyScreenLayerChanged();
      return;
    }
    if (collection is List) {
      if (add) {
        if (!collection.contains(action.value)) collection.add(action.value);
      } else {
        collection.remove(action.value);
      }
      _notifyScreenLayerChanged();
    }
  }

  void _applyFunctionAction(RenPyScreenAction action) {
    final name = action.functionName;
    if (name == null) return;
    final args = <String>[
      for (final value in action.positional) _literalForArg(value),
      for (final entry in action.keywords.entries)
        '${entry.key}=${_literalForArg(entry.value)}',
    ];
    final call = '$name(${args.join(', ')})';
    try {
      _pythonEvaluator.evaluate(call, _pythonScope);
      _notifyScreenLayerChanged();
    } on RenPyPythonError {
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.skippedScreen,
          message: 'Skipped unsupported screen Function action.',
          detail: action.raw,
        ),
      );
    }
  }

  dynamic _evaluateExpression(String expression) {
    final value = expression.trim();

    // The imagemap shim and the older literal handling predate the Python
    // evaluator; keep them ahead so their existing behavior is preserved.
    final imagemapResult = _renpyImagemapResult(value);
    if (imagemapResult != null) return imagemapResult;

    // Try the real Python-subset evaluator first; it covers calls, methods,
    // subscripts, comprehensions, f-strings and the like. Anything outside the
    // supported subset (including an unknown bare name) throws, and we fall
    // back to the previous literal/passthrough handling so nothing regresses.
    try {
      return _pythonEvaluator.evaluate(value, _pythonScope);
    } on RenPyPythonError {
      // Fall through to the legacy handling below.
    }

    return _evaluateExpressionFallback(value);
  }

  dynamic _evaluateExpressionFallback(String value) {
    if (value == 'True' || value == 'true') return true;
    if (value == 'False' || value == 'false') return false;
    if (value == 'None' || value == 'null') return null;
    if (RegExp(r'^\[\s*\]$').hasMatch(value)) return <dynamic>[];

    final quoted = RegExp(r'''^["'](.*)["']$''').firstMatch(value);
    if (quoted != null) return quoted.group(1);

    final integer = int.tryParse(value);
    if (integer != null) return integer;

    final decimal = double.tryParse(value);
    if (decimal != null) return decimal;

    return value;
  }

  /// Resolve the label name for a `jump expression` / `call expression`
  /// statement, whose target is a Python expression rather than a literal
  /// label. Handles a bare variable holding the name, a quoted string
  /// literal, and simple string concatenation with variable substitution.
  String _resolveDynamicTarget(String expression) {
    final trimmed = expression.trim();

    final lookup = _lookupVariable(trimmed);
    if (lookup.found) {
      return lookup.value?.toString() ?? trimmed;
    }

    final evaluated = RenPyArithmetic.evaluate(trimmed, _variables);
    if (evaluated != null) {
      return evaluated.toString();
    }

    return _evaluateExpression(trimmed).toString();
  }

  bool _evaluateCondition(String condition) {
    // Prefer the Python-subset evaluator, which understands calls, method
    // calls, subscripting and richer comparisons than the legacy condition
    // splitter. On any unsupported construct fall back to the older evaluator
    // so previously-passing conditions keep working.
    try {
      return RenPyPythonEvaluator.truthy(
        _pythonEvaluator.evaluate(condition, _pythonScope),
      );
    } on RenPyPythonError {
      // Fall through to the legacy condition evaluator.
    }

    return RenPyExpressionEvaluator(
      lookupVariable: _lookupExpressionVariable,
      evaluateLiteral: _evaluateExpression,
    ).evaluateCondition(condition);
  }

  RenPyExpressionVariable _lookupExpressionVariable(String name) {
    final lookup = _lookupVariable(name);
    return RenPyExpressionVariable(lookup.found, lookup.value);
  }

  _VariableLookup _lookupVariable(String name) {
    final persistentField = _persistentFieldName(name);
    if (persistentField != null) {
      return _VariableLookup(
        _persistent.containsKey(persistentField),
        _persistent[persistentField],
      );
    }

    // config./gui. names resolve through the shared scope so the legacy
    // condition/expression fallbacks see the same seeded values the Python
    // evaluator does.
    if (name.startsWith('config.') || name.startsWith('gui.')) {
      return _VariableLookup(_pythonScope.has(name), _pythonScope.read(name));
    }

    // `store.x` is the explicit spelling of the default namespace, so it reads
    // the same backing slot as the bare name `x`.
    if (name.startsWith('store.')) {
      final field = name.substring('store.'.length);
      return _VariableLookup(_variables.containsKey(field), _variables[field]);
    }

    return _VariableLookup(_variables.containsKey(name), _variables[name]);
  }

  String? _persistentFieldName(String name) {
    const prefix = 'persistent.';
    if (!name.startsWith(prefix)) return null;

    final field = name.substring(prefix.length);
    return field.isEmpty ? null : field;
  }

  /// Start or resume execution.
  void run() {
    if (_state == RenPyRunnerState.complete ||
        _state == RenPyRunnerState.error) {
      // Reset to beginning, re-initializing per-game state.
      _position = 0;
      _currentBlock = script.statements;
      _currentLabel = null;
      _pendingDialogue = null;
      _stack.clear();
      _errorMessage = null;
      _state = RenPyRunnerState.ready;
      _resetScriptState();
    }

    if (_state == RenPyRunnerState.ready ||
        _state == RenPyRunnerState.waitingForInput) {
      _state = RenPyRunnerState.running;
      _executeNext();
    }
  }

  /// Execute the next statement in the script.
  void _executeNext() {
    // 1  finished the current block?
    if (_position >= _currentBlock.length) {
      if (_stack.isNotEmpty) {
        // Pop back to the parent context (e.g., we're done with a menu branch)
        final ctx = _stack.removeLast();
        _currentBlock = ctx.block;
        _position = ctx.position;
        // A loop body that ran to its end re-enters the loop statement to
        // re-check the condition (while) or advance the iterator (for).
        if (ctx.kind == _ExecutionContextKind.loop) {
          return _reenterLoop(ctx.loop!);
        }
        return _executeNext(); // continue immediately
      }

      // The call stack is empty. In RenPy a label's block ending without a
      // jump/return does not stop the script: execution falls through to the
      // statement that textually follows the block's owner in source order,
      // climbing the enclosing-block chain. Only when there is genuinely no
      // following statement does the script complete.
      final fallthrough = _fallThrough(_currentBlock);
      if (fallthrough != null) {
        _currentBlock = fallthrough.block;
        _position = fallthrough.position;
        return _executeNext();
      }

      _currentLabel = null;
      _complete();
      return;
    }

    final stmt = _currentBlock[_position];
    try {
      _executeStatement(stmt);
    } catch (e) {
      _state = RenPyRunnerState.error;
      _errorMessage = 'Error executing statement: $e';
    }
  }

  /// Execute a single statement.
  void _executeStatement(RenPyStatement stmt) {
    if (stmt is RenPySayStatement) {
      _executeSayStatement(stmt);
    } else if (stmt is RenPyLabelStatement) {
      _executeLabelStatement(stmt);
    } else if (stmt is RenPyJumpStatement) {
      _executeJumpStatement(stmt);
    } else if (stmt is RenPyMenuStatement) {
      _executeMenuStatement(stmt);
    } else if (stmt is RenPyShowStatement) {
      _executeShowStatement(stmt);
    } else if (stmt is RenPySceneStatement) {
      _executeSceneStatement(stmt);
    } else if (stmt is RenPyImageStatement) {
      _executeImageStatement(stmt);
    } else if (stmt is RenPyWithStatement) {
      _executeWithStatement(stmt);
    } else if (stmt is RenPyPythonStatement) {
      _executePythonStatement(stmt);
    } else if (stmt is RenPyDefineStatement) {
      _executeDefineStatement(stmt);
    } else if (stmt is RenPyDefaultStatement) {
      _executeDefaultStatement(stmt);
    } else if (stmt is RenPyIfStatement) {
      _executeIfStatement(stmt);
    } else if (stmt is RenPyWhileStatement) {
      _executeWhileStatement(stmt);
    } else if (stmt is RenPyForStatement) {
      _executeForStatement(stmt);
    } else if (stmt is RenPyLoopControlStatement) {
      _executeLoopControlStatement(stmt);
    } else if (stmt is RenPyPlayStatement) {
      _executePlayStatement(stmt);
    } else if (stmt is RenPyQueueStatement) {
      _executeQueueStatement(stmt);
    } else if (stmt is RenPyVoiceStatement) {
      _executeVoiceStatement(stmt);
    } else if (stmt is RenPyStopStatement) {
      _executeStopStatement(stmt);
    } else if (stmt is RenPyHideStatement) {
      _executeHideStatement(stmt);
    } else if (stmt is RenPyReturnStatement) {
      _executeReturnStatement(stmt);
    } else if (stmt is RenPyCallStatement) {
      _executeCallStatement(stmt);
    } else if (stmt is RenPyNvlStatement) {
      _executeNvlStatement(stmt);
    } else if (stmt is RenPyInitStatement || stmt is RenPyInitOffsetStatement) {
      // Init metadata is applied before runtime or has no runtime effect.
      _position++;
      _executeNext();
    } else if (stmt is RenPyScreenStatement || stmt is RenPyStyleStatement) {
      // Screen/style declarations are UI metadata, not script runtime steps.
      _position++;
      _executeNext();
    } else if (stmt is RenPyTransformStatement) {
      // Transform declarations are referenced by later image placement clauses.
      _position++;
      _executeNext();
    } else if (stmt is RenPyPassStatement) {
      // Do nothing
      _position++;
      _executeNext();
    } else if (stmt is RenPyWindowStatement) {
      // `window show` / `window hide` / `window auto` control the visibility of
      // the (empty) dialogue window between lines. With no dialogue window
      // renderer in this runner they have no engine-visible effect, so treat
      // them as advancing no-ops rather than unknown statements.
      _position++;
      _executeNext();
    } else if (stmt is RenPyPauseStatement) {
      _executePauseStatement(stmt);
    } else {
      // Unknown statement type, just skip it.
      print('Warning: Unknown statement type: ${stmt.runtimeType}');
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.unknownStatement,
          message: 'Skipped unknown RenPy statement.',
          detail: stmt.runtimeType.toString(),
        ),
      );
      _position++;
      _executeNext();
    }
  }

  /// Execute a say statement (dialogue).
  void _executeSayStatement(RenPySayStatement stmt) {
    // A `extend` continues the prior line and so should not interrupt its voice.
    if (stmt.character != 'extend') {
      _interruptVoiceForDialogue();
    }
    final isExtend = stmt.character == 'extend';
    final previous = _lastDialogueEvent;
    final event =
        isExtend && previous != null
            ? RenPyDialogueEvent(
              characterId: previous.characterId,
              displayName: previous.displayName,
              text: '${previous.text}${stmt.text ?? ''}',
              color: previous.color,
            )
            : isExtend
            ? RenPyDialogueEvent(text: stmt.text ?? '')
            : _dialogueEventForSayStatement(stmt);

    // `@`-say temporary attributes swap the speaker's sprite for this one line.
    _applyTemporaryAttributes(stmt);

    _position++;

    // Interior {w}/{p} waits always pause, even when the line ends with {nw}.
    final waitTag = _firstInlineWaitTag(event.text);
    if (waitTag != null) {
      _pendingDialogue = _PendingDialogue(event, waitTag.end);
      _emitDialogueEvent(
        _dialogueEventWithText(
          event,
          event.text.substring(0, waitTag.end),
          autoContinueDuration: waitTag.duration,
        ),
      );
      _state = RenPyRunnerState.waitingForInput;
      return;
    }

    _emitDialogueEvent(event);

    // A trailing {nw} suppresses only the terminal wait.
    if (_hasNoWaitTag(event.text)) {
      _revertTemporaryAttributes();
      _executeNext();
      return;
    }

    // Wait for player input.
    _state = RenPyRunnerState.waitingForInput;
  }

  /// Emits a SHOW event applying [stmt]'s `@` temporary attributes to the
  /// speaker's currently-shown sprite, recording the prior image for revert.
  /// Best-effort: a narrator line, a speaker with no shown sprite, or an
  /// unresolvable tag does nothing (no diagnostic, no throw).
  void _applyTemporaryAttributes(RenPySayStatement stmt) {
    if (stmt.temporaryAttributes.isEmpty) return;
    final speaker = stmt.character;
    if (speaker == null) return;

    // Resolve the sprite tag: the character's `image=` keyword if defined,
    // otherwise the speaker id itself.
    final tag = (_characters[speaker]?['image'] as String?) ?? speaker;
    final shown = _shownImageNames[tag];
    if (shown == null) return;

    final tempName = '$tag ${stmt.temporaryAttributes.join(' ')}';
    onImageEvent?.call(RenPyImageEvent.show(tempName));
    if (onImage != null) onImage!(null, tempName, null);
    _pendingAttributeRevert = shown;
  }

  /// Re-shows the sprite captured by [_applyTemporaryAttributes], reverting the
  /// temporary `@`-say attribute swap once the line is dismissed.
  void _revertTemporaryAttributes() {
    final revert = _pendingAttributeRevert;
    if (revert == null) return;
    _pendingAttributeRevert = null;
    onImageEvent?.call(RenPyImageEvent.show(revert));
    if (onImage != null) onImage!(null, revert, null);
  }

  /// Execute a `pause`/`pause <duration>` statement, mirroring the
  /// `$ renpy.pause(...)` path: fire [onPause] with the same event payload, then
  /// wait for input/timeout and advance. A bare `pause` (no duration) behaves
  /// like the existing "wait for input" pause.
  void _executePauseStatement(RenPyPauseStatement stmt) {
    final duration =
        stmt.duration == null ? null : _renpyPauseDuration(stmt.duration!);
    onPause?.call(RenPyPauseEvent(duration: duration));
    _state = RenPyRunnerState.waitingForInput;
    _position++;
  }

  bool _hasNoWaitTag(String text) => RegExp(r'\{nw\}').hasMatch(text);

  static final RegExp _inlineWaitTagPattern = RegExp(
    r'\{(?:w|p)(?:=([0-9]+(?:\.[0-9]+)?|\.[0-9]+))?\}',
  );

  _InlineWaitTag? _firstInlineWaitTag(String text, {int start = 0}) {
    final match = _inlineWaitTagPattern.matchAsPrefix(text, start);
    if (match != null) {
      return _InlineWaitTag(
        end: match.end,
        duration: double.tryParse(match.group(1) ?? ''),
      );
    }

    final next = _inlineWaitTagPattern.allMatches(text, start).firstOrNull;
    if (next == null) return null;
    return _InlineWaitTag(
      end: next.end,
      duration: double.tryParse(next.group(1) ?? ''),
    );
  }

  RenPyDialogueEvent _dialogueEventWithText(
    RenPyDialogueEvent event,
    String text, {
    double? autoContinueDuration,
  }) {
    return RenPyDialogueEvent(
      characterId: event.characterId,
      displayName: event.displayName,
      text: text,
      color: event.color,
      autoContinueDuration: autoContinueDuration,
    );
  }

  void _continuePendingDialogue(_PendingDialogue pending) {
    final waitTag = _firstInlineWaitTag(
      pending.event.text,
      start: pending.searchStart,
    );
    if (waitTag != null) {
      _pendingDialogue = _PendingDialogue(pending.event, waitTag.end);
      _emitDialogueEvent(
        _dialogueEventWithText(
          pending.event,
          pending.event.text.substring(0, waitTag.end),
          autoContinueDuration: waitTag.duration,
        ),
      );
      _state = RenPyRunnerState.waitingForInput;
      return;
    }

    _pendingDialogue = null;
    _emitDialogueEvent(pending.event);
    if (_hasNoWaitTag(pending.event.text)) {
      // Mirror the no-pending {nw} path: a `@`-say sprite swap must revert
      // before advancing so the temporary attribute does not leak into the
      // next line on the interior-wait + trailing-{nw} combination.
      _revertTemporaryAttributes();
      _executeNext();
      return;
    }
    _state = RenPyRunnerState.waitingForInput;
  }

  RenPyDialogueEvent _dialogueEventForSayStatement(RenPySayStatement stmt) {
    // Resolve character name if it's a defined character.
    String? displayName;
    String? color;
    if (stmt.character != null && _characters.containsKey(stmt.character)) {
      displayName = _characters[stmt.character]!['name'] as String?;
      color = _characters[stmt.character]!['color'] as String?;
    } else {
      displayName = stmt.character;
    }

    return RenPyDialogueEvent(
      characterId: stmt.character,
      displayName: displayName,
      text: stmt.text ?? '',
      color: color,
    );
  }

  void _emitDialogueEvent(RenPyDialogueEvent event) {
    _lastDialogueEvent = event;
    onDialogueEvent?.call(event);

    // Display the dialogue.
    if (onDialogue != null) {
      onDialogue!(event.displayName, event.text);
    }
  }

  /// Execute a label statement.
  void _executeLabelStatement(RenPyLabelStatement stmt) {
    _currentLabel = stmt.name;
    _stack.add(
      _ExecutionContext(
        _currentBlock,
        _position + 1,
        _ExecutionContextKind.labelFallthrough,
      ),
    );
    _currentBlock = stmt.block;
    _position = 0;
    _executeNext();
  }

  /// Execute a jump statement.
  void _executeJumpStatement(RenPyJumpStatement stmt) {
    final target =
        stmt.isExpression ? _resolveDynamicTarget(stmt.target) : stmt.target;
    final context = _findLabelContext(target);
    if (context == null) {
      throw Exception('Label not found: $target');
    }

    _discardNonCallContexts();
    _prepareLabelContext(context);
    _executeNext();
  }

  /// Execute a menu statement.
  void _executeMenuStatement(RenPyMenuStatement stmt) {
    final items =
        stmt.items
            .where(
              (choice) =>
                  _evaluateCondition(choice.condition) &&
                  !_menuSetContains(stmt.setVariable, choice.text),
            )
            .toList();
    if (items.isEmpty) {
      _position++;
      _executeNext();
      return;
    }

    // No callback?  Fall back to first choice.
    if (onMenu == null) {
      _executeMenuChoice(items.first);
      return;
    }

    final choices = items.map((c) => c.text).toList();
    onMenu!(choices, (index) => _executeMenuChoice(items[index]), stmt.caption);

    // Wait for UI / test harness.
    _state = RenPyRunnerState.waitingForInput;
  }

  /// Execute a menu choice.
  void _executeMenuChoice(MenuChoice choice) {
    final menu = _currentBlock[_position];
    if (menu is RenPyMenuStatement) {
      _recordMenuSetChoice(menu.setVariable, choice.text);
    }

    // Resume after this statement when the branch ends.
    _stack.add(
      _ExecutionContext(
        _currentBlock,
        _position + 1,
        _ExecutionContextKind.block,
      ),
    );

    if (choice.block.isEmpty) {
      // Nothing inside -> behave like "pass".
      _currentBlock = _stack.removeLast().block;
      _position++; // Resume after menu statement.
      return _executeNext();
    }

    _currentBlock = choice.block;
    _position = 0;
    _state = RenPyRunnerState.running; // We just answered - keep going.
    _executeNext();
  }

  bool _menuSetContains(String? setVariable, String choice) {
    if (setVariable == null) return false;
    final value = _variables[setVariable];
    return value is Iterable && value.contains(choice);
  }

  void _recordMenuSetChoice(String? setVariable, String choice) {
    if (setVariable == null) return;
    final value = _variables[setVariable];
    if (value is List) {
      if (!value.contains(choice)) value.add(choice);
      return;
    }
    if (value is Iterable) {
      // Some other iterable already tracks chosen items; rebuild it as a list
      // preserving the existing members rather than replacing it outright.
      final items = value.toList();
      if (!items.contains(choice)) items.add(choice);
      _variables[setVariable] = items;
      return;
    }
    if (value != null) {
      // A pre-existing scalar is not a set/list. Preserve it as the first
      // member instead of silently clobbering unrelated state.
      _variables[setVariable] = <dynamic>[value, choice];
      return;
    }
    _variables[setVariable] = <String>[choice];
  }

  /// Execute a show statement.
  void _executeShowStatement(RenPyShowStatement stmt) {
    // `show screen name(args)` adds to the screen layer rather than the image
    // layer. The parser keeps the leading `screen` token as part of the image
    // name, so detect it here.
    if (_isScreenDirective(stmt.imageName)) {
      _showScreen(_stripScreenKeyword(stmt.imageName));
      _emitInlineTransition(stmt.withExpression);
      _position++;
      _executeNext();
      return;
    }

    final placement = _placementFor(stmt.atExpression);
    _diagnosePlacement(placement);
    final layers = _resolveLayeredImageLayers(
      stmt.imageName,
      stmt.onLayerExpression,
    );
    onImageEvent?.call(
      RenPyImageEvent.show(
        stmt.imageName,
        at: stmt.atExpression,
        placement: placement,
        onLayer: stmt.onLayerExpression,
        zOrder: _parseZOrder(stmt.zOrderExpression),
        behind: stmt.behindExpression,
        displayableText: stmt.displayableText,
        layers: layers,
      ),
    );
    if (onImage != null) {
      onImage!(null, stmt.imageName, null);
    }
    _recordShownImage(stmt.imageName);
    _emitInlineTransition(stmt.withExpression);

    _position++;
    _executeNext();
  }

  /// Records the currently-shown image name for its tag so the `@`-say
  /// temporary-attribute swap can detect and later revert the sprite.
  void _recordShownImage(String imageName) {
    final tag = _imageTag(imageName);
    if (tag.isEmpty) return;
    _shownImageNames[tag] = imageName.split('#').first.trim();
  }

  /// Resolves a `show <layeredimage> <attrs...>` into the ordered list of layer
  /// image names to stack, updating the per-sprite active-attribute state. The
  /// first show of a tag seeds each group's `default`; later shows merge in the
  /// named attributes, swapping only their groups. Returns an empty list for a
  /// non-layeredimage show (the caller falls back to single-image rendering).
  List<String> _resolveLayeredImageLayers(String? imageName, String? onLayer) {
    if (imageName == null || !_layeredImages.isLayeredImage(imageName)) {
      return const [];
    }

    final tag = _imageTag(imageName);
    final key =
        '${onLayer?.trim().isNotEmpty == true ? onLayer!.trim() : 'master'}::$tag';
    final base =
        _layeredImageAttributes[key] ??
        _layeredImages.defaultAttributes(imageName);
    final merged = _layeredImages.mergeAttributes(imageName, base);
    _layeredImageAttributes[key] = merged;

    return _layeredImages.resolveLayers(
      imageName,
      merged,
      evaluateCondition: _evaluateCondition,
    );
  }

  String _imageTag(String imageName) {
    final clean = imageName.split('#').first.trim();
    if (clean.isEmpty) return clean;
    return clean.split(RegExp(r'\s+')).first;
  }

  int? _parseZOrder(String? expression) {
    final value = expression?.trim();
    if (value == null || value.isEmpty) return null;
    return int.tryParse(value);
  }

  RenPyImagePlacement? _placementFor(String? expression) {
    final value = expression?.trim();
    if (value == null || value.isEmpty) return null;

    final parsed = RenPyImagePlacement.parse(value);
    if (parsed == null || parsed.isSupported) return parsed;

    return _transformPlacements[value] ??
        _transformPlacements[_transformName(value)] ??
        parsed;
  }

  /// Execute a scene statement.
  void _executeSceneStatement(RenPySceneStatement stmt) {
    final placement = _placementFor(stmt.atExpression);
    _diagnosePlacement(placement);
    // A scene clears its layer, so drop the layeredimage attribute state for it.
    final sceneLayer =
        stmt.onLayerExpression?.trim().isNotEmpty == true
            ? stmt.onLayerExpression!.trim()
            : 'master';
    _layeredImageAttributes.removeWhere(
      (key, _) => key.startsWith('$sceneLayer::'),
    );
    // A scene clears the image layer, so any shown sprites are gone.
    _shownImageNames.clear();
    onImageEvent?.call(
      RenPyImageEvent.scene(
        stmt.imageName,
        at: stmt.atExpression,
        placement: placement,
        onLayer: stmt.onLayerExpression,
        zOrder: _parseZOrder(stmt.zOrderExpression),
      ),
    );
    if (onImage != null) {
      onImage!(stmt.imageName, null, null);
    }
    _emitInlineTransition(stmt.withExpression);

    _position++;
    _executeNext();
  }

  void _executeHideStatement(RenPyHideStatement stmt) {
    // `hide screen name` removes a screen from the screen layer.
    if (_isScreenDirective(stmt.imageName)) {
      _hideScreen(_stripScreenKeyword(stmt.imageName));
      _emitInlineTransition(stmt.withExpression);
      _position++;
      _executeNext();
      return;
    }

    final hideTag = _imageTag(stmt.imageName);
    final hideLayer =
        stmt.onLayerExpression?.trim().isNotEmpty == true
            ? stmt.onLayerExpression!.trim()
            : 'master';
    _layeredImageAttributes.remove('$hideLayer::$hideTag');
    _shownImageNames.remove(hideTag);

    onImageEvent?.call(
      RenPyImageEvent.hide(stmt.imageName, onLayer: stmt.onLayerExpression),
    );
    if (onImage != null) {
      onImage!(null, null, stmt.imageName);
    }
    _emitInlineTransition(stmt.withExpression);

    _position++;
    _executeNext();
  }

  void _executeImageStatement(RenPyImageStatement stmt) {
    onImageDefinition?.call(
      RenPyImageDefinitionEvent(name: stmt.name, expression: stmt.expression),
    );

    _position++;
    _executeNext();
  }

  void _emitInlineTransition(String? transition) {
    if (transition == null || transition.trim().isEmpty) return;
    _emitTransition(transition);
  }

  /// Execute a with statement.
  void _executeWithStatement(RenPyWithStatement stmt) {
    _emitTransition(stmt.transition);

    _position++;
    _executeNext();
  }

  void _emitTransition(String transition) {
    final name = transition.trim();
    final intent = _transitionResolver.resolve(name);
    if (intent?.fidelity == RenPyTransitionFidelity.unsupported) {
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.unsupportedTransition,
          message: 'Unsupported RenPy transition expression.',
          detail: intent?.expression ?? name,
        ),
      );
    }
    onTransition?.call(RenPyTransitionEvent(name, intent: intent));
  }

  /// Execute a Python statement.
  void _executePythonStatement(RenPyPythonStatement stmt) {
    // A multi-line `python:` block is never a single assignment/audio/pause
    // statement, so route it straight to the statement executor. The
    // single-statement fast paths below use `dotAll` regexes that would
    // otherwise misread the whole block as one giant assignment value.
    if (stmt.code.contains('\n')) {
      if (_tryExecutePythonBlock(stmt.code)) {
        _position++;
        _executeNext();
        return;
      }
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.skippedPython,
          message: 'Skipped unsupported Python statement.',
          detail: stmt.code,
        ),
      );
      _position++;
      _executeNext();
      return;
    }

    final assignment = _pythonAssignment(stmt.code);
    if (assignment != null) {
      final value = _evaluateExpression(assignment.expression);
      _setVariable(assignment.name, value);
      _position++;
      _executeNext();
      return;
    }

    final augmentedAssignment = _pythonAugmentedAssignment(stmt.code);
    if (augmentedAssignment != null) {
      _applyAugmentedAssignment(augmentedAssignment);
      _position++;
      _executeNext();
      return;
    }

    if (_isRenpyFullRestart(stmt.code)) {
      _complete();
      return;
    }

    final audio = _renpyAudioEvent(stmt.code);
    if (_applyAudioChannelRegistration(stmt.code)) {
      _position++;
      _executeNext();
      return;
    }

    if (audio != null) {
      onAudio?.call(audio);
      _position++;
      _executeNext();
      return;
    }

    final pause = _renpyPauseEvent(stmt.code);
    if (pause != null) {
      onPause?.call(pause);
      _state = RenPyRunnerState.waitingForInput;
      _position++;
      return;
    }

    if (_tryExecuteRenpySay(stmt.code)) return;

    if (_isRecognizedNoOpPythonCall(stmt.code)) {
      _position++;
      _executeNext();
      return;
    }

    // A bare expression-statement (e.g. `items.append(3)`) is in scope: run it
    // for its side effects. Only treat it as handled when the Python-subset
    // evaluator accepts it; otherwise fall through to the diagnostic so genuine
    // statements (control flow, `def`, multi-line blocks) are not swallowed.
    if (_tryEvaluatePythonExpressionStatement(stmt.code)) {
      _position++;
      _executeNext();
      return;
    }

    // General Python statement execution: multi-line `python:` blocks plus any
    // `$` statement the targeted fast paths above did not claim (control flow,
    // `def`, subscript/attribute assignment, tuple unpacking, ...). On any
    // unsupported construct or runtime failure this throws and we fall through
    // to the skip diagnostic, so an unsupported block never aborts the script.
    if (_tryExecutePythonBlock(stmt.code)) {
      _position++;
      _executeNext();
      return;
    }

    _emitDiagnostic(
      RenPyDiagnostic(
        code: RenPyDiagnosticCode.skippedPython,
        message: 'Skipped unsupported Python statement.',
        detail: stmt.code,
      ),
    );

    _position++;
    _executeNext();
  }

  /// Runs [code] through the Python statement executor against the live store.
  /// Returns `true` when it executed cleanly, `false` when the executor threw a
  /// [RenPyPythonError] (so the caller falls back to the skip diagnostic).
  bool _tryExecutePythonBlock(String code) {
    if (code.trim().isEmpty) return true;
    try {
      _pythonExecutor.execute(code, _pythonScope);
      // A block may have written `persistent.*`; persist those changes since
      // the scope writes the map directly without going through _setVariable.
      _flushPersistent();
      return true;
    } on RenPyPythonError {
      return false;
    }
  }

  void _diagnosePlacement(RenPyImagePlacement? placement) {
    if (placement == null || placement.isSupported) return;
    _emitDiagnostic(
      RenPyDiagnostic(
        code: RenPyDiagnosticCode.unsupportedPlacement,
        message: 'Unsupported RenPy image placement expression.',
        detail: placement.expression,
      ),
    );
  }

  void _emitDiagnostic(RenPyDiagnostic diagnostic) {
    final callback = _onDiagnostic;
    if (callback != null) {
      callback(diagnostic);
    } else {
      // No callback wired yet (e.g. a load-time skip during construction);
      // buffer it so it is delivered once a host assigns [onDiagnostic].
      _pendingDiagnostics.add(diagnostic);
    }
  }

  /// Evaluates [code] as a single Python expression for its side effects,
  /// such as `items.append(x)` or `data.update(other)`. Returns `true` when the
  /// evaluator accepted the expression (so the caller advances), `false` when
  /// it falls outside the supported subset (so the caller can diagnose it).
  bool _tryEvaluatePythonExpressionStatement(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return false;
    // Skip anything containing a statement-level construct the expression
    // evaluator must not interpret (assignments are handled separately, and
    // semicolons/newlines indicate multiple statements).
    if (trimmed.contains('\n') || trimmed.contains(';')) return false;
    try {
      _pythonEvaluator.evaluate(trimmed, _pythonScope);
      return true;
    } on RenPyPythonError {
      return false;
    }
  }

  _PythonAssignment? _pythonAssignment(String code) {
    final match = RegExp(
      r'^([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*=\s*(.+)$',
      dotAll: true,
    ).firstMatch(code.trim());
    if (match == null) return null;
    return _PythonAssignment(match.group(1)!, match.group(2)!);
  }

  _PythonAugmentedAssignment? _pythonAugmentedAssignment(String code) {
    // Order matters: the longer operators (//=, **=) must precede the single
    // character forms so the regex does not stop at the first character.
    final match = RegExp(
      r'^([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*(\/\/|\*\*|[+\-*/%])=\s*(.+)$',
      dotAll: true,
    ).firstMatch(code.trim());
    if (match == null) return null;
    return _PythonAugmentedAssignment(
      match.group(1)!,
      match.group(2)!,
      match.group(3)!,
    );
  }

  void _applyAugmentedAssignment(_PythonAugmentedAssignment assignment) {
    final lookup = _lookupVariable(assignment.name);
    final right = _evaluateExpression(assignment.expression);
    final left = lookup.found ? lookup.value : _defaultAugmentedValue(right);
    final value = _applyPythonOperator(
      assignment.name,
      left,
      assignment.operator,
      right,
    );
    if (value == _augmentedUnchanged) {
      // The operation could not be applied (type mismatch, division by zero,
      // and similar). Leave the variable untouched and surface a diagnostic
      // rather than silently overwriting it with the right-hand value.
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.skippedPython,
          message: 'Skipped unsupported augmented assignment.',
          detail:
              '${assignment.name} ${assignment.operator}= '
              '${assignment.expression}',
        ),
      );
      return;
    }
    _setVariable(assignment.name, value);
  }

  dynamic _defaultAugmentedValue(dynamic right) {
    if (right is num) return 0;
    if (right is String) return '';
    return null;
  }

  /// Sentinel returned by [_applyPythonOperator] when the operation could not
  /// be carried out and the target variable should be left unchanged.
  static const Object _augmentedUnchanged = Object();

  dynamic _applyPythonOperator(
    String name,
    dynamic left,
    String operator,
    dynamic right,
  ) {
    // Floor division and power are not exposed by RenPyArithmetic, so handle
    // them here with the existing numeric operands.
    if (operator == '//' || operator == '**') {
      if (left is! num || right is! num) return _augmentedUnchanged;
      if (operator == '//') {
        if (right == 0) return _augmentedUnchanged;
        final quotient = (left / right).floorToDouble();
        return left is int && right is int ? quotient.toInt() : quotient;
      }
      final powered = math.pow(left, right);
      return left is int && right is int && right >= 0
          ? powered.toInt()
          : powered.toDouble();
    }

    // String concatenation and repetition keep their direct handling so a
    // non-numeric operand still composes the way Python would.
    if (operator == '+' && left is String && right is String) {
      return left + right;
    }
    if (operator == '*' && left is String && right is int) {
      return left * right;
    }
    if (operator == '*' && left is int && right is String) {
      return right * left;
    }

    if (left is! num || right is! num) return _augmentedUnchanged;

    // Reuse the arithmetic layer for the remaining numeric operators. The
    // operands are already resolved values, so feed them through dedicated
    // variable names to avoid re-parsing literals.
    final result = RenPyArithmetic.evaluate('__lhs__ $operator __rhs__', {
      '__lhs__': left,
      '__rhs__': right,
    });
    // RenPyArithmetic returns null on division/modulo by zero or other
    // failures; treat that as "leave unchanged" since both operands are known
    // numbers here.
    return result ?? _augmentedUnchanged;
  }

  void _setVariable(String name, dynamic value) {
    final persistentField = _persistentFieldName(name);
    if (persistentField != null) {
      _persistent[persistentField] = value;
      _flushPersistent();
      return;
    }

    // config./gui. assignments flow into their scope maps rather than a flat
    // store key so subsequent reads resolve them as namespaced names.
    if (name.startsWith('config.') || name.startsWith('gui.')) {
      _pythonScope.write(name, value);
      return;
    }

    // `store.x` is the explicit spelling of the default store namespace, so it
    // writes the same backing slot as the bare name `x`. This mirrors
    // _lookupVariable's read aliasing so a runtime `$ store.x = ...` is visible
    // both as `store.x` and bare `x` (without this, the read path strips the
    // prefix while the write kept the literal `store.x` key, so the value was
    // lost).
    if (name.startsWith('store.')) {
      _variables[name.substring('store.'.length)] = value;
      return;
    }

    _variables[name] = value;
  }

  bool _isRecognizedNoOpPythonCall(String code) {
    return RegExp(
      r'^MasterClock\.AddTime\s*\((.*)\)$',
      dotAll: true,
    ).hasMatch(code.trim());
  }

  String? _renpyImagemapResult(String expression) {
    if (!expression.trimLeft().startsWith('renpy.imagemap')) return null;

    final hotspot = RegExp(
      r'''\(\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*,\s*["']([^"']+)["']\s*\)''',
    ).firstMatch(expression);
    return hotspot?.group(1);
  }

  bool _isRenpyFullRestart(String code) {
    return RegExp(r'^renpy\.full_restart\s*\(\s*\)$').hasMatch(code.trim());
  }

  bool _applyAudioChannelRegistration(String code) {
    final registration = _renpyRegisterChannel(code);
    if (registration == null) return false;
    _audioChannels[registration.name] = _AudioChannelRegistration(
      mixer: registration.mixer,
      loop: registration.loop,
    );
    return true;
  }

  _AudioChannelRegistrationCall? _renpyRegisterChannel(String code) {
    final match = RegExp(
      r'^renpy\.music\.register_channel\s*\((.*)\)$',
      dotAll: true,
    ).firstMatch(code.trim());
    if (match == null) return null;

    final _PythonCallArguments(:positional, :keywords) = _pythonCallArguments(
      match.group(1)!,
    );

    final nameExpression =
        keywords['name'] ?? (positional.isNotEmpty ? positional[0] : null);
    final mixerExpression =
        keywords['mixer'] ?? (positional.length > 1 ? positional[1] : null);
    if (nameExpression == null || mixerExpression == null) return null;

    final loopExpression = keywords['loop'];
    return _AudioChannelRegistrationCall(
      name: _evaluateExpression(nameExpression).toString(),
      mixer: _evaluateExpression(mixerExpression).toString(),
      loop:
          loopExpression == null
              ? null
              : _evaluateExpression(loopExpression) == true,
    );
  }

  RenPyAudioEvent? _renpyAudioEvent(String code) {
    final trimmed = code.trim();
    final musicStart = RegExp(
      r'''^renpy\.music_start\s*\(\s*(.+?)\s*\)$''',
    ).firstMatch(trimmed);
    if (musicStart != null) {
      return RenPyAudioEvent.play(
        channel: 'music',
        asset: _evaluateAudioAsset(musicStart.group(1)!),
      );
    }

    final play = RegExp(
      r'''^renpy\.play\s*\(\s*(.+?)\s*\)$''',
    ).firstMatch(trimmed);
    if (play != null) {
      return RenPyAudioEvent.play(
        channel: 'sound',
        asset: _evaluateAudioAsset(play.group(1)!),
      );
    }

    final musicPlay = RegExp(
      r'''^renpy\.music\.play\s*\((.*)\)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (musicPlay != null) {
      return _renpyAudioPlayHelperEvent(
        musicPlay.group(1)!,
        defaultChannel: 'music',
      );
    }

    final musicStop = RegExp(
      r'''^renpy\.music\.stop\s*\((.*)\)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (musicStop != null) {
      return _renpyAudioStopHelperEvent(
        musicStop.group(1)!,
        defaultChannel: 'music',
      );
    }

    final soundPlay = RegExp(
      r'''^renpy\.sound\.play\s*\((.*)\)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (soundPlay != null) {
      return _renpyAudioPlayHelperEvent(
        soundPlay.group(1)!,
        defaultChannel: 'sound',
      );
    }

    final soundStop = RegExp(
      r'''^renpy\.sound\.stop\s*\((.*)\)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (soundStop != null) {
      return _renpyAudioStopHelperEvent(
        soundStop.group(1)!,
        defaultChannel: 'sound',
      );
    }

    return null;
  }

  RenPyAudioEvent? _renpyAudioPlayHelperEvent(
    String arguments, {
    required String defaultChannel,
  }) {
    final _PythonCallArguments(:positional, :keywords) = _pythonCallArguments(
      arguments,
    );
    final assetExpression =
        keywords['filenames'] ??
        keywords['filename'] ??
        (positional.isNotEmpty ? positional[0] : null);
    if (assetExpression == null) return null;

    final channel =
        _pythonAudioString(
          keywords['channel'] ?? (positional.length > 1 ? positional[1] : null),
        ) ??
        defaultChannel;
    final registration = _audioChannels[channel];
    return RenPyAudioEvent.play(
      channel: channel,
      asset: _evaluateAudioAsset(assetExpression),
      fadeout: _pythonAudioString(keywords['fadeout']),
      fadein: _pythonAudioString(keywords['fadein']),
      volume: _pythonAudioString(
        keywords['relative_volume'] ?? keywords['volume'],
      ),
      ifChanged: _pythonAudioBool(keywords['if_changed']) == true ? true : null,
      mixer: registration?.mixer,
      loop: _pythonAudioBool(keywords['loop']) ?? registration?.loop,
    );
  }

  RenPyAudioEvent _renpyAudioStopHelperEvent(
    String arguments, {
    required String defaultChannel,
  }) {
    final _PythonCallArguments(:positional, :keywords) = _pythonCallArguments(
      arguments,
    );
    final channel =
        _pythonAudioString(
          keywords['channel'] ?? (positional.isNotEmpty ? positional[0] : null),
        ) ??
        defaultChannel;
    return RenPyAudioEvent.stop(
      channel: channel,
      fadeout: _pythonAudioString(keywords['fadeout']),
    );
  }

  String? _pythonAudioString(String? expression) {
    if (expression == null) return null;
    final value = _evaluateExpression(expression);
    return value?.toString();
  }

  bool? _pythonAudioBool(String? expression) {
    if (expression == null) return null;
    return _evaluateExpression(expression) == true;
  }

  /// Handles a bare `renpy.say(who, what, interact=...)` statement, the
  /// programmatic form of a say line. The Python `renpy.*` dispatch does not
  /// model `say` (it needs the dialogue pipeline), so it is intercepted here
  /// before falling back: a None/empty `who` emits a narrator line, otherwise
  /// the speaker is resolved like a say statement's character. `interact=False`
  /// advances without blocking for input; otherwise the runner waits as it
  /// would after a normal say. Returns true when the call was claimed.
  bool _tryExecuteRenpySay(String code) {
    final match = RegExp(
      r'^renpy\.say\s*\((.*)\)$',
      dotAll: true,
    ).firstMatch(code.trim());
    if (match == null) return false;

    final args = _pythonCallArguments(match.group(1)!);
    // `renpy.say(who, what)` - who is positional[0], what is positional[1].
    // `what` may also arrive as the `what=` keyword.
    final whatExpr =
        args.positional.length > 1 ? args.positional[1] : args.keywords['what'];
    if (whatExpr == null) return false;

    final whoExpr =
        args.positional.isNotEmpty
            ? args.positional.first
            : args.keywords['who'];

    // `_evaluateExpression` never throws - it falls back to a literal so an
    // unresolvable argument still emits a best-effort line rather than aborting.
    final what = _evaluateExpression(whatExpr);
    final who = whoExpr == null ? null : _evaluateExpression(whoExpr);

    final interactExpr = args.keywords['interact'];
    final interactive = interactExpr == null || interactExpr.trim() != 'False';

    final speaker = _renpySaySpeaker(who, whoExpr);
    final event = _dialogueEventForRenpySay(speaker, what?.toString() ?? '');

    _position++;
    _emitDialogueEvent(event);

    if (interactive) {
      _state = RenPyRunnerState.waitingForInput;
    } else {
      _executeNext();
    }
    return true;
  }

  /// Resolves the speaker id for `renpy.say`. A None/empty `who` is the
  /// narrator (null id). When `who` resolves to a Character whose store name is
  /// the source expression (e.g. `renpy.say(e, "Hi")`), that bare name is used
  /// so a defined character's display name/color is applied.
  String? _renpySaySpeaker(Object? who, String? whoExpr) {
    if (who == null) {
      final trimmed = whoExpr?.trim();
      if (trimmed == null || trimmed.isEmpty || trimmed == 'None') return null;
      // A bare identifier naming a defined character is used directly.
      if (_characters.containsKey(trimmed)) return trimmed;
      return null;
    }
    final text = who.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Builds the dialogue event for a `renpy.say`. When [speaker] names a defined
  /// character its display name/color are applied; otherwise [speaker] is shown
  /// verbatim (or null for the narrator).
  RenPyDialogueEvent _dialogueEventForRenpySay(String? speaker, String text) {
    if (speaker != null && _characters.containsKey(speaker)) {
      return RenPyDialogueEvent(
        characterId: speaker,
        displayName: _characters[speaker]!['name'] as String?,
        text: text,
        color: _characters[speaker]!['color'] as String?,
      );
    }
    return RenPyDialogueEvent(
      characterId: speaker,
      displayName: speaker,
      text: text,
    );
  }

  RenPyPauseEvent? _renpyPauseEvent(String code) {
    final match = RegExp(r'^renpy\.pause\s*\((.*)\)$').firstMatch(code.trim());
    if (match == null) return null;

    final duration = _renpyPauseDuration(match.group(1)!);
    return RenPyPauseEvent(duration: duration);
  }

  double? _renpyPauseDuration(String arguments) {
    final positional =
        _splitPythonArguments(arguments)
            .map((argument) => argument.trim())
            .where((argument) => argument.isNotEmpty && !argument.contains('='))
            .firstOrNull;
    if (positional == null) return null;
    return double.tryParse(positional);
  }

  _PythonCallArguments _pythonCallArguments(String arguments) {
    final positional = <String>[];
    final keywords = <String, String>{};
    for (final argument in _splitPythonArguments(arguments)) {
      final trimmed = argument.trim();
      if (trimmed.isEmpty) continue;
      final keyword = RegExp(
        r'^([a-zA-Z_]\w*)\s*=\s*(.+)$',
        dotAll: true,
      ).firstMatch(trimmed);
      if (keyword != null) {
        keywords[keyword.group(1)!] = keyword.group(2)!.trim();
      } else {
        positional.add(trimmed);
      }
    }
    return _PythonCallArguments(positional: positional, keywords: keywords);
  }

  List<String> _splitPythonArguments(String arguments) {
    final parts = <String>[];
    final current = StringBuffer();
    String? quote;
    var escaped = false;
    var depth = 0;
    for (final codeUnit in arguments.codeUnits) {
      final character = String.fromCharCode(codeUnit);
      if (escaped) {
        current.write(character);
        escaped = false;
        continue;
      }
      if (character == r'\') {
        current.write(character);
        escaped = true;
        continue;
      }
      if (quote != null) {
        current.write(character);
        if (character == quote) quote = null;
        continue;
      }
      if (character == '"' || character == "'") {
        current.write(character);
        quote = character;
        continue;
      }
      if (character == '(' || character == '[' || character == '{') {
        depth += 1;
        current.write(character);
        continue;
      }
      if (character == ')' || character == ']' || character == '}') {
        if (depth > 0) depth -= 1;
        current.write(character);
        continue;
      }
      if (character == ',' && depth == 0) {
        parts.add(current.toString());
        current.clear();
        continue;
      }
      current.write(character);
    }
    parts.add(current.toString());
    return parts;
  }

  /// Execute a define statement.
  void _executeDefineStatement(RenPyDefineStatement stmt) {
    // Most define statements are handled during initialization but we still need to handle runtime definitions.
    _applyDefinition(stmt.name, stmt.expression);

    _position++;
    _executeNext();
  }

  void _executeDefaultStatement(RenPyDefaultStatement stmt) {
    _applyDefault(stmt.name, stmt.expression);

    _position++;
    _executeNext();
  }

  /// Execute an if statement
  void _executeIfStatement(RenPyIfStatement stmt) {
    IfEntry? entry;
    for (final candidate in stmt.entries) {
      if (_evaluateCondition(candidate.condition)) {
        entry = candidate;
        break;
      }
    }

    if (entry != null) {
      _stack.add(
        _ExecutionContext(
          _currentBlock,
          _position + 1,
          _ExecutionContextKind.block,
        ),
      );
      _currentBlock = entry.block;
      _position = 0;
      _executeNext();
    } else {
      _position++;
      _executeNext();
    }
  }

  /// Execute a top-level `while` loop. Each pass re-evaluates the condition and,
  /// when true, runs the body block with a loop frame so the body's end returns
  /// here. A high iteration cap protects against a runaway condition.
  void _executeWhileStatement(RenPyWhileStatement stmt) {
    final iterations = (_whileIterationCounts[stmt] ?? 0);
    if (iterations >= _maxScriptLoopIterations) {
      _whileIterationCounts.remove(stmt);
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.unknownStatement,
          message:
              'while loop exceeded $_maxScriptLoopIterations iterations; '
              'aborting to avoid a hang.',
          detail: stmt.condition,
        ),
      );
      _exitLoop();
      return;
    }

    if (!_evaluateCondition(stmt.condition)) {
      _whileIterationCounts.remove(stmt);
      _exitLoop();
      return;
    }

    _whileIterationCounts[stmt] = iterations + 1;
    _enterLoopBody(stmt, stmt.block);
  }

  /// Execute a top-level `for` loop. On first entry the iterable is evaluated
  /// and its items captured; each pass binds the loop variable to the next item
  /// and runs the body, returning here when the body ends.
  void _executeForStatement(RenPyForStatement stmt) {
    var state = _forLoopStates[stmt];
    if (state == null) {
      final items = _iterableForExpression(stmt.iterable);
      if (items == null) {
        // Unevaluable iterable: skip the loop gracefully.
        _emitDiagnostic(
          RenPyDiagnostic(
            code: RenPyDiagnosticCode.unknownStatement,
            message: 'Skipped for loop over an unevaluable iterable.',
            detail: stmt.iterable,
          ),
        );
        _exitLoop();
        return;
      }
      state = _ForLoopState(items);
      _forLoopStates[stmt] = state;
    }

    if (state.index >= state.items.length) {
      _forLoopStates.remove(stmt);
      _exitLoop();
      return;
    }

    final item = state.items[state.index];
    state.index += 1;
    _bindLoopVariable(stmt.variable, item);
    _enterLoopBody(stmt, stmt.block);
  }

  /// Pushes a loop frame and descends into [body]. When [body] ends, the loop
  /// frame routes control back through [_reenterLoop] to [loop].
  void _enterLoopBody(RenPyStatement loop, List<RenPyStatement> body) {
    _stack.add(
      _ExecutionContext(
        _currentBlock,
        _position,
        _ExecutionContextKind.loop,
        loop: loop,
      ),
    );
    if (body.isEmpty) {
      // Empty body: re-enter immediately rather than descending into nothing.
      _stack.removeLast();
      _reenterLoop(loop);
      return;
    }
    _currentBlock = body;
    _position = 0;
    _executeNext();
  }

  /// Re-runs a loop statement after its body block finished one pass. The loop
  /// frame has already been popped and [_currentBlock]/[_position] restored to
  /// the loop statement, so executing it re-checks the condition / advances.
  void _reenterLoop(RenPyStatement loop) {
    if (loop is RenPyWhileStatement) {
      _executeWhileStatement(loop);
    } else if (loop is RenPyForStatement) {
      _executeForStatement(loop);
    } else {
      // Defensive: nothing to re-enter, fall through past it.
      _position++;
      _executeNext();
    }
  }

  /// Continues execution at the statement after a loop once it has exhausted or
  /// been broken out of. The loop statement sits at [_currentBlock]/[_position].
  void _exitLoop() {
    _position++;
    _executeNext();
  }

  /// Execute a `break` / `continue` inside a top-level loop. Unwinds the stack
  /// to the nearest loop frame: `break` exits past the loop; `continue` re-runs
  /// the loop statement (re-check condition / advance iterator).
  void _executeLoopControlStatement(RenPyLoopControlStatement stmt) {
    while (_stack.isNotEmpty) {
      final top = _stack.last;
      if (top.kind == _ExecutionContextKind.call) {
        // Do not unwind across a call boundary; a stray break/continue here is
        // a no-op, matching RenPy's tolerance of out-of-loop control.
        break;
      }
      _stack.removeLast();
      if (top.kind == _ExecutionContextKind.loop) {
        _currentBlock = top.block;
        _position = top.position;
        final loop = top.loop!;
        if (stmt.action == RenPyLoopControlAction.breakLoop) {
          if (loop is RenPyWhileStatement) _whileIterationCounts.remove(loop);
          if (loop is RenPyForStatement) _forLoopStates.remove(loop);
          _exitLoop();
        } else {
          _reenterLoop(loop);
        }
        return;
      }
    }

    // No enclosing loop frame: treat as a no-op and continue.
    _position++;
    _executeNext();
  }

  /// Binds a `for` loop target to [item] in the store. Supports a single name
  /// and simple tuple unpacking (`for i, v in ...`). RenPy leaves the loop
  /// variable assigned in the store after the loop, which this mirrors.
  void _bindLoopVariable(String target, Object? item) {
    final names =
        target
            .replaceAll('(', '')
            .replaceAll(')', '')
            .split(',')
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toList();
    if (names.length <= 1) {
      _setVariable(target.trim(), item);
      return;
    }

    if (item is Iterable) {
      final values = item.toList();
      for (var i = 0; i < names.length && i < values.length; i += 1) {
        _setVariable(names[i], values[i]);
      }
      return;
    }
    // Not unpackable: bind the whole item to the first name.
    _setVariable(names.first, item);
  }

  /// Evaluates a `for` iterable expression to a list of items, or null when it
  /// cannot be turned into an iterable. Lists/sets iterate their elements,
  /// maps iterate their keys (Python semantics) and strings their characters.
  List<Object?>? _iterableForExpression(String expression) {
    final value = _evaluateExpression(expression);
    if (value is List) return List<Object?>.of(value);
    if (value is Set) return value.toList();
    if (value is Map) return value.keys.toList();
    if (value is Iterable) return value.toList();
    if (value is String) return value.split('');
    return null;
  }

  /// Execute a play statement.
  void _executePlayStatement(RenPyPlayStatement stmt) {
    final registration = _audioChannels[stmt.channel];
    final audio = _evaluateAudioPlayExpression(stmt.expression);
    onAudio?.call(
      RenPyAudioEvent.play(
        fadeout: audio.fadeout,
        volume: audio.volume,
        ifChanged: audio.ifChanged,
        channel: stmt.channel,
        asset: audio.asset,
        fadein: audio.fadein,
        mixer: registration?.mixer,
        loop: audio.loop ?? registration?.loop,
      ),
    );
    _position++;
    _executeNext();
  }

  void _executeStopStatement(RenPyStopStatement stmt) {
    if (stmt.channel == 'voice') {
      _voiceActive = false;
      _voiceSustain = false;
    }
    onAudio?.call(
      RenPyAudioEvent.stop(channel: stmt.channel, fadeout: stmt.fadeout),
    );
    _position++;
    _executeNext();
  }

  /// Execute a queue statement: append to the channel's playlist instead of
  /// replacing the current track.
  void _executeQueueStatement(RenPyQueueStatement stmt) {
    final registration = _audioChannels[stmt.channel];
    final audio = _evaluateAudioPlayExpression(stmt.expression);
    onAudio?.call(
      RenPyAudioEvent.queue(
        fadeout: audio.fadeout,
        volume: audio.volume,
        channel: stmt.channel,
        asset: audio.asset,
        fadein: audio.fadein,
        mixer: registration?.mixer,
        loop: audio.loop ?? registration?.loop,
      ),
    );
    _position++;
    _executeNext();
  }

  /// Execute a `voice` statement. Voice is one-shot on the dedicated voice
  /// channel: this implicitly interrupts any prior voice. `voice sustain`
  /// instead keeps the currently playing voice alive across the next line.
  void _executeVoiceStatement(RenPyVoiceStatement stmt) {
    if (stmt.isSustain) {
      _voiceSustain = true;
      _position++;
      _executeNext();
      return;
    }

    final asset = _evaluateAudioAsset(stmt.expression);
    final registration = _audioChannels['voice'];
    // Starting a new voice replaces the prior one; the play event itself stops
    // the current voice track on the channel, so no separate stop is emitted.
    onAudio?.call(
      RenPyAudioEvent.play(
        channel: 'voice',
        asset: asset,
        mixer: registration?.mixer,
        loop: false,
      ),
    );
    _voiceActive = true;
    _voiceSustain = false;
    _voiceJustStarted = true;
    _position++;
    _executeNext();
  }

  /// Stops a one-shot voice when the next dialogue line arrives, mirroring
  /// RenPy's automatic voice interruption. The dialogue line that a `voice`
  /// statement precedes keeps that voice playing; the line after it interrupts.
  /// A preceding `voice sustain` keeps the voice alive for one extra line.
  void _interruptVoiceForDialogue() {
    if (!_voiceActive) return;
    if (_voiceJustStarted) {
      _voiceJustStarted = false;
      return;
    }
    if (_voiceSustain) {
      _voiceSustain = false;
      return;
    }
    _voiceActive = false;
    onAudio?.call(const RenPyAudioEvent.stop(channel: 'voice'));
  }

  String _evaluateAudioAsset(String expression) {
    final trimmed = expression.trim();
    final quoted = RegExp(r'''^["']([^"']+)["']''').firstMatch(trimmed);
    if (quoted != null) return quoted.group(1)!;

    final value = _evaluateExpression(trimmed);
    final stringValue = value?.toString() ?? trimmed;
    return stringValue.split(RegExp(r'\s+')).first;
  }

  _AudioPlayExpression _evaluateAudioPlayExpression(String expression) {
    final parts = _audioExpressionParts(expression);
    return _AudioPlayExpression(
      asset: _evaluateAudioAsset(parts.assetExpression),
      fadein: _audioModifierValue(parts.modifiers, 'fadein'),
      loop: _audioLoopModifier(parts.modifiers),
      fadeout: _audioModifierValue(parts.modifiers, 'fadeout'),
      volume: _audioModifierValue(parts.modifiers, 'volume'),
      ifChanged: parts.modifiers.contains('if_changed') ? true : null,
    );
  }

  _AudioExpressionParts _audioExpressionParts(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return const _AudioExpressionParts(
        assetExpression: '',
        modifiers: <String>[],
      );
    }

    final splitIndex = _audioAssetExpressionEnd(trimmed);
    final assetExpression = trimmed.substring(0, splitIndex).trim();
    final modifierText = trimmed.substring(splitIndex).trim();
    return _AudioExpressionParts(
      assetExpression: assetExpression,
      modifiers:
          modifierText.isEmpty
              ? const <String>[]
              : modifierText.split(RegExp(r'\s+')),
    );
  }

  int _audioAssetExpressionEnd(String expression) {
    final quote = expression[0];
    if (quote == '"' || quote == "'") {
      var escaped = false;
      for (var index = 1; index < expression.length; index += 1) {
        final character = expression[index];
        if (escaped) {
          escaped = false;
          continue;
        }
        if (character == r'\') {
          escaped = true;
          continue;
        }
        if (character == quote) return index + 1;
      }
      return expression.length;
    }

    final whitespace = RegExp(r'\s').firstMatch(expression);
    return whitespace?.start ?? expression.length;
  }

  String? _audioModifierValue(List<String> modifiers, String name) {
    for (var index = 0; index < modifiers.length - 1; index += 1) {
      if (modifiers[index] == name) return modifiers[index + 1];
    }
    return null;
  }

  bool? _audioLoopModifier(List<String> modifiers) {
    bool? loop;
    for (final modifier in modifiers) {
      switch (modifier) {
        case 'loop':
          loop = true;
        case 'noloop':
          loop = false;
      }
    }
    return loop;
  }

  void _executeReturnStatement(RenPyReturnStatement stmt) {
    while (_stack.isNotEmpty) {
      final ctx = _stack.removeLast();
      if (ctx.kind == _ExecutionContextKind.call) {
        _currentBlock = ctx.block;
        _position = ctx.position;
        _currentLabel = ctx.callerLabel;
        _state = RenPyRunnerState.running;
        _executeNext();
        return;
      }
    }

    _complete();
  }

  void _executeCallStatement(RenPyCallStatement stmt) {
    // `call screen name(args)` blocks for a Return value from the screen. The
    // screen name and its (evaluated) invocation arguments are registered as a
    // blocking call screen; a controller supplies the result via
    // executeScreenAction(Return(v)). See the call-screen notes in the runtime.
    if (stmt.isScreen) {
      _registerCallScreen(stmt);
      return;
    }

    final target =
        stmt.isExpression ? _resolveDynamicTarget(stmt.target) : stmt.target;

    final context = _findLabelContext(target);
    if (context == null) {
      throw Exception('Label not found: $target');
    }

    _stack.add(
      _ExecutionContext(
        _currentBlock,
        _position + 1,
        _ExecutionContextKind.call,
        callerLabel: _currentLabel,
      ),
    );
    _enterLabelTarget(context);
    _executeNext();
  }

  /// Moves execution into a resolved jump/call target. For a `label` it
  /// descends into the label's block; for a named `menu` it runs the menu
  /// statement in place so its choices are presented.
  void _enterLabelTarget(_LabelContext context) {
    _currentLabel = context.name;
    final label = context.label;
    if (label == null) {
      _currentBlock = context.parentBlock;
      _position = context.index;
      return;
    }
    _currentBlock = label.block;
    _position = 0;
  }

  /// Registers a blocking `call screen` request and waits for a Return value.
  ///
  /// The screen name and its (evaluated) invocation arguments are recorded as
  /// the pending call screen and exposed via [pendingCallScreen] so a renderer
  /// can resolve and draw it as a modal overlay. The runner blocks here;
  /// `executeScreenAction(Return(v))` resolves it, lands the value in `_return`,
  /// and advances past the call statement.
  void _registerCallScreen(RenPyCallStatement stmt) {
    final name = stmt.screenName ?? 'screen';
    final args = stmt.screenArgs;
    var positional = const <Object?>[];
    var keywords = const <String, Object?>{};
    if (args != null && args.trim().isNotEmpty) {
      final parsed = _pythonCallArguments(args);
      positional = [
        for (final expression in parsed.positional)
          _evaluateExpression(expression),
      ];
      keywords = <String, Object?>{
        for (final entry in parsed.keywords.entries)
          entry.key: _evaluateExpression(entry.value),
      };
    }
    final shown = RenPyShownScreen(
      name: name,
      tag: name,
      positional: positional,
      keywords: keywords,
      isCall: true,
    );
    _callScreen = shown;
    if (!hasScreen(name)) {
      _emitDiagnostic(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.skippedScreen,
          message:
              'call screen references an unknown screen; blocking for '
              'Return().',
          detail: name,
        ),
      );
    }
    _notifyScreenLayerChanged();
    // Advance past the call statement now; the Return value lands in `_return`.
    // RenPy blocks the script here until Return; we mirror that by waiting.
    _position++;
    _state = RenPyRunnerState.waitingForInput;
  }

  /// Whether a screen named [name] is registered.
  bool hasScreen(String name) => _screens.containsKey(name);

  void _executeNvlStatement(RenPyNvlStatement stmt) {
    switch (stmt.action) {
      case RenPyNvlAction.clear:
        _lastDialogueEvent = null;
    }

    _position++;
    _executeNext();
  }

  /// Handle user input (continue after dialogue).
  void continueExecution() {
    if (_state == RenPyRunnerState.waitingForInput) {
      _state = RenPyRunnerState.running;
      final pending = _pendingDialogue;
      if (pending != null) {
        _continuePendingDialogue(pending);
        return;
      }
      // The swapped line is now dismissed: revert the `@`-say sprite swap.
      _revertTemporaryAttributes();
      _executeNext();
    }
  }

  /// Captures enough execution state to resume this runner later.
  RenPyRunnerSnapshot snapshot() {
    return RenPyRunnerSnapshot(
      state: _state.name,
      currentLabel: _currentLabel,
      currentBlockPath: _pathForBlock(_currentBlock),
      position: _position,
      stack:
          _stack
              .map(
                (context) => RenPyRunnerSnapshotStackFrame(
                  blockPath: _pathForBlock(context.block),
                  position: context.position,
                  kind: context.kind.name,
                  callerLabel: context.callerLabel,
                ),
              )
              .toList(),
      variables: Map<String, dynamic>.of(_variables),
      persistent: Map<String, dynamic>.of(_persistent),
      characters: _snapshotCharacters(),
      lastDialogue: _snapshotDialogue(_lastDialogueEvent),
      pendingDialogue:
          _pendingDialogue == null
              ? null
              : RenPyRunnerSnapshotPendingDialogue(
                event: _snapshotDialogue(_pendingDialogue!.event)!,
                searchStart: _pendingDialogue!.searchStart,
              ),
      errorMessage: _errorMessage,
    );
  }

  /// Restores a snapshot captured from an equivalent parsed script.
  void restoreSnapshot(RenPyRunnerSnapshot snapshot) {
    _stack
      ..clear()
      ..addAll(
        snapshot.stack.map((frame) {
          final block = _blockForPath(frame.blockPath);
          final kind = _contextKindFor(frame.kind);
          // A loop frame's block/position point at the loop statement itself;
          // recover that statement so the body's end can re-enter the loop.
          RenPyStatement? loop;
          if (kind == _ExecutionContextKind.loop &&
              frame.position >= 0 &&
              frame.position < block.length) {
            final statement = block[frame.position];
            if (statement is RenPyWhileStatement ||
                statement is RenPyForStatement) {
              loop = statement;
            }
          }
          return _ExecutionContext(
            block,
            frame.position,
            kind,
            callerLabel: frame.callerLabel,
            loop: loop,
          );
        }),
      );
    _currentBlock = _blockForPath(snapshot.currentBlockPath);
    _position = snapshot.position;
    _currentLabel = snapshot.currentLabel;
    _state = _runnerStateFor(snapshot.state);
    _errorMessage = snapshot.errorMessage;
    _variables
      ..clear()
      ..addAll(snapshot.variables);
    _persistent
      ..clear()
      ..addAll(snapshot.persistent);
    _characters
      ..clear()
      ..addAll(
        snapshot.characters.map(
          (name, values) => MapEntry(name, Map<String, dynamic>.of(values)),
        ),
      );
    _lastDialogueEvent = snapshot.lastDialogue?.toDialogueEvent();
    _pendingDialogue =
        snapshot.pendingDialogue == null
            ? null
            : _PendingDialogue(
              snapshot.pendingDialogue!.event.toDialogueEvent(),
              snapshot.pendingDialogue!.searchStart,
            );
    _flushPersistent();
  }

  /// Jump to a specific label.
  void jumpToLabel(String label) {
    final context = _findLabelContext(label);
    if (context == null) {
      throw Exception('Label not found: $label');
    }

    _stack.clear();
    _forLoopStates.clear();
    _whileIterationCounts.clear();
    _pendingDialogue = null;
    _prepareLabelContext(context);
    _state = RenPyRunnerState.ready;
  }

  /// Records the owner (parent block + owning-statement index) of every nested
  /// statement block reachable from the script, so [_fallThrough] can continue
  /// in source order when a block ends. Descends through every block-bearing
  /// statement: labels, `init`, `if`/`elif`/`else` entries, and menu choices.
  void _buildBlockOwners() {
    void register(List<RenPyStatement> block) {
      for (var index = 0; index < block.length; index += 1) {
        final statement = block[index];
        if (statement is RenPyIfStatement) {
          for (final entry in statement.entries) {
            _blockOwners[entry.block] = _BlockOwner(block, index);
            register(entry.block);
          }
        } else if (statement is RenPyMenuStatement) {
          for (final item in statement.items) {
            _blockOwners[item.block] = _BlockOwner(block, index);
            register(item.block);
          }
        } else if (statement is RenPyBlockStatement) {
          _blockOwners[statement.block] = _BlockOwner(block, index);
          register(statement.block);
        }
      }
    }

    register(script.statements);
  }

  /// Resolves RenPy label fall-through for [block] when it ends with no call
  /// frame to return to: execution continues with the statement that textually
  /// follows the block's owner in source order. When that owner is the last
  /// statement in its own (parent) block, the search climbs to the parent's
  /// owner, recursing up to the top level. Returns the next context to run, or
  /// null when there is genuinely no following statement (the script ends).
  _ExecutionContext? _fallThrough(List<RenPyStatement> block) {
    var current = block;
    while (true) {
      final owner = _blockOwners[current];
      if (owner == null) return null;
      final next = owner.ownerIndex + 1;
      if (next < owner.parentBlock.length) {
        return _ExecutionContext(
          owner.parentBlock,
          next,
          _ExecutionContextKind.labelFallthrough,
        );
      }
      current = owner.parentBlock;
    }
  }

  _LabelContext? _findLabelContext(String name) {
    _LabelContext? search(List<RenPyStatement> block) {
      for (var index = 0; index < block.length; index += 1) {
        final statement = block[index];
        if (statement is RenPyLabelStatement && statement.name == name) {
          return _LabelContext(statement, block, index, name);
        }
        // A named menu (`menu name:`) is a jump/call target too: re-entering it
        // runs the menu in place so its choices are presented again.
        if (statement is RenPyMenuStatement && statement.name == name) {
          return _LabelContext(statement, block, index, name);
        }

        if (statement is RenPyBlockStatement) {
          final nested = search(statement.block);
          if (nested != null) return nested;
        }
        // Menu choice blocks can themselves contain labels or named menus.
        if (statement is RenPyMenuStatement) {
          for (final item in statement.items) {
            final nested = search(item.block);
            if (nested != null) return nested;
          }
        }
      }
      return null;
    }

    return search(script.statements);
  }

  void _prepareLabelContext(_LabelContext context) {
    _currentLabel = context.name;

    final label = context.label;
    if (label == null) {
      // A named menu target: run the menu statement in place. Fall-through after
      // it is resolved through the block-owner chain, like any other statement.
      _currentBlock = context.parentBlock;
      _position = context.index;
      return;
    }

    _currentBlock = label.block;
    _position = 0;

    final nextPosition = context.index + 1;
    if (nextPosition < context.parentBlock.length) {
      _stack.add(
        _ExecutionContext(
          context.parentBlock,
          nextPosition,
          _ExecutionContextKind.labelFallthrough,
        ),
      );
    }
  }

  void _discardNonCallContexts() {
    var discardedLoop = false;
    while (_stack.isNotEmpty &&
        _stack.last.kind != _ExecutionContextKind.call) {
      if (_stack.last.kind == _ExecutionContextKind.loop) discardedLoop = true;
      _stack.removeLast();
    }
    // A jump out of a loop abandons its iteration; re-reaching the loop later
    // re-evaluates the condition/iterable from scratch, so drop any held state.
    if (discardedLoop) {
      _forLoopStates.clear();
      _whileIterationCounts.clear();
    }
  }

  RenPyRunnerState _runnerStateFor(String name) {
    return RenPyRunnerState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => throw ArgumentError.value(name, 'snapshot.state'),
    );
  }

  _ExecutionContextKind _contextKindFor(String name) {
    return _ExecutionContextKind.values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => throw ArgumentError.value(name, 'snapshot.stack.kind'),
    );
  }

  List<RenPyRunnerBlockPathSegment> _pathForBlock(List<RenPyStatement> target) {
    if (identical(target, script.statements)) {
      return const <RenPyRunnerBlockPathSegment>[];
    }

    final path = _findBlockPath(
      target,
      script.statements,
      const <RenPyRunnerBlockPathSegment>[],
    );
    if (path == null) {
      throw StateError('Unable to snapshot an execution block outside script.');
    }
    return path;
  }

  List<RenPyRunnerBlockPathSegment>? _findBlockPath(
    List<RenPyStatement> target,
    List<RenPyStatement> block,
    List<RenPyRunnerBlockPathSegment> prefix,
  ) {
    for (var index = 0; index < block.length; index += 1) {
      final statement = block[index];

      if (statement is RenPyIfStatement) {
        for (
          var entryIndex = 0;
          entryIndex < statement.entries.length;
          entryIndex += 1
        ) {
          final childPath = <RenPyRunnerBlockPathSegment>[
            ...prefix,
            RenPyRunnerBlockPathSegment(
              statementIndex: index,
              branch: RenPyRunnerBlockPathBranch.ifEntry,
              childIndex: entryIndex,
            ),
          ];
          final childBlock = statement.entries[entryIndex].block;
          if (identical(target, childBlock)) return childPath;
          final nested = _findBlockPath(target, childBlock, childPath);
          if (nested != null) return nested;
        }
        continue;
      }

      if (statement is RenPyMenuStatement) {
        for (
          var choiceIndex = 0;
          choiceIndex < statement.items.length;
          choiceIndex += 1
        ) {
          final childPath = <RenPyRunnerBlockPathSegment>[
            ...prefix,
            RenPyRunnerBlockPathSegment(
              statementIndex: index,
              branch: RenPyRunnerBlockPathBranch.menuChoice,
              childIndex: choiceIndex,
            ),
          ];
          final childBlock = statement.items[choiceIndex].block;
          if (identical(target, childBlock)) return childPath;
          final nested = _findBlockPath(target, childBlock, childPath);
          if (nested != null) return nested;
        }
        continue;
      }

      if (statement is RenPyBlockStatement) {
        final childPath = <RenPyRunnerBlockPathSegment>[
          ...prefix,
          RenPyRunnerBlockPathSegment(
            statementIndex: index,
            branch: RenPyRunnerBlockPathBranch.block,
          ),
        ];
        if (identical(target, statement.block)) return childPath;
        final nested = _findBlockPath(target, statement.block, childPath);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  List<RenPyStatement> _blockForPath(List<RenPyRunnerBlockPathSegment> path) {
    var block = script.statements;
    for (final segment in path) {
      if (segment.statementIndex < 0 ||
          segment.statementIndex >= block.length) {
        throw StateError('Invalid runner snapshot block path.');
      }
      final statement = block[segment.statementIndex];
      switch (segment.branch) {
        case RenPyRunnerBlockPathBranch.block:
          if (statement is! RenPyBlockStatement) {
            throw StateError('Snapshot path expected a block statement.');
          }
          block = statement.block;
        case RenPyRunnerBlockPathBranch.ifEntry:
          if (statement is! RenPyIfStatement ||
              segment.childIndex == null ||
              segment.childIndex! < 0 ||
              segment.childIndex! >= statement.entries.length) {
            throw StateError('Snapshot path expected an if entry.');
          }
          block = statement.entries[segment.childIndex!].block;
        case RenPyRunnerBlockPathBranch.menuChoice:
          if (statement is! RenPyMenuStatement ||
              segment.childIndex == null ||
              segment.childIndex! < 0 ||
              segment.childIndex! >= statement.items.length) {
            throw StateError('Snapshot path expected a menu choice.');
          }
          block = statement.items[segment.childIndex!].block;
      }
    }
    return block;
  }

  Map<String, Map<String, dynamic>> _snapshotCharacters() {
    return _characters.map(
      (name, values) => MapEntry(name, Map<String, dynamic>.of(values)),
    );
  }

  RenPyRunnerSnapshotDialogue? _snapshotDialogue(RenPyDialogueEvent? event) {
    return event == null ? null : RenPyRunnerSnapshotDialogue.fromEvent(event);
  }

  /// Reset the runner to the beginning.
  ///
  /// Per-game script state is cleared and the define/default initialization is
  /// re-run so a restart starts from a clean slate. The [_persistent]
  /// namespace is intentionally preserved: Ren'Py persistent data (seen text,
  /// achievements, preferences) is meant to survive across games.
  void reset() {
    _stack.clear();
    _pendingDialogue = null;
    _position = 0;
    _currentBlock = script.statements;
    _currentLabel = null;
    _state = RenPyRunnerState.ready;
    _errorMessage = null;
    _resetScriptState();
  }

  /// Clears per-game state and re-applies define/default initialization.
  ///
  /// [_persistent] is deliberately left untouched so cross-game data persists.
  void _resetScriptState() {
    _forLoopStates.clear();
    _whileIterationCounts.clear();
    _variables.clear();
    // config/gui derive entirely from define/default and are rebuilt by
    // _processDefines below; clear them so a restart re-seeds from a clean
    // slate. _persistent is deliberately not cleared so it survives the reset.
    _config.clear();
    _gui.clear();
    _characters.clear();
    _audioChannels.clear();
    _transformPlacements.clear();
    _transforms.clear();
    _screens.clear();
    _styles.clear();
    _shownScreens.clear();
    _callScreen = null;
    _screenRuntime = null;
    // Re-seed so a restart replays the same deterministic random sequence.
    _renpyRandom = math.Random(_renpyRandomSeed);
    _lastDialogueEvent = null;
    _voiceActive = false;
    _voiceSustain = false;
    _voiceJustStarted = false;
    _transitionResolver = RenPyTransitionResolver.fromScript(script);
    _seedConfigDefaults();
    _processDefines();
  }

  void _complete() {
    _state = RenPyRunnerState.complete;
    _flushPersistent();
  }

  void _flushPersistent() {
    _persistentStore?.save(_persistent);
  }

  /// Emits a play event for a `renpy.music.queue(...)` / `renpy.sound.play(...)`
  /// call evaluated inside an expression. Arguments arrive already evaluated, so
  /// the asset and channel are read directly rather than re-parsed. The volume
  /// setters have no audio-event analogue and are handled as no-ops by the API.
  void _emitRenpyApiAudio(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    final defaultChannel = function.startsWith('music') ? 'music' : 'sound';
    final asset =
        (keywords['filenames'] ??
                keywords['filename'] ??
                (positional.isNotEmpty ? positional.first : null))
            ?.toString();
    if (asset == null) return;
    final channel =
        (keywords['channel'] ?? (positional.length > 1 ? positional[1] : null))
            ?.toString() ??
        defaultChannel;
    final registration = _audioChannels[channel];
    final loop =
        keywords['loop'] is bool
            ? keywords['loop'] as bool
            : registration?.loop;
    if (function.endsWith('.queue')) {
      onAudio?.call(
        RenPyAudioEvent.queue(
          channel: channel,
          asset: asset,
          loop: loop,
          mixer: registration?.mixer,
        ),
      );
      return;
    }
    onAudio?.call(
      RenPyAudioEvent.play(
        channel: channel,
        asset: asset,
        loop: loop,
        mixer: registration?.mixer,
      ),
    );
  }

  /// Emits a one-shot voice play for `renpy.voice("file")` (best-effort). A bare
  /// `renpy.voice_sustain()` keeps the current voice alive across the next line.
  void _emitRenpyVoice(List<Object?> positional) {
    final asset = positional.isNotEmpty ? positional.first?.toString() : null;
    if (asset == null || asset.isEmpty) return;
    final registration = _audioChannels['voice'];
    onAudio?.call(
      RenPyAudioEvent.play(
        channel: 'voice',
        asset: asset,
        mixer: registration?.mixer,
        loop: false,
      ),
    );
    _voiceActive = true;
    _voiceSustain = false;
    _voiceJustStarted = true;
  }

  void _emitRenpyVoiceSustain() {
    if (_voiceActive) _voiceSustain = true;
  }
}

/// Wires the `renpy.*` shims to the runner. Random is deterministic (sourced
/// from the runner's seeded generator), `notify` routes to [RenPyRunner.onNotify],
/// `audio` emits play events for `music.queue`/`sound.play` (the volume setters
/// are no-ops), and the remaining handled calls return neutral values. Anything
/// outside the dispatched subset is rejected by the interpreter and falls back.
class _RunnerRenPyApi implements RenPyApi {
  _RunnerRenPyApi(this._runner);

  final RenPyRunner _runner;

  @override
  bool variant(Object? name) => false;

  @override
  double randomRandom() => _runner._renpyRandom.nextDouble();

  @override
  int randomRandint(int a, int b) {
    if (b < a) return a;
    return a + _runner._renpyRandom.nextInt(b - a + 1);
  }

  @override
  Object? randomChoice(List<Object?> sequence) {
    if (sequence.isEmpty) return null;
    return sequence[_runner._renpyRandom.nextInt(sequence.length)];
  }

  @override
  void notify(Object? message) {
    _runner.onNotify?.call(message?.toString() ?? '');
  }

  @override
  String input(Object? prompt) => '';

  @override
  void withStatement(Object? transition) {}

  @override
  void audio(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    if (function.endsWith('set_volume')) return;
    if (function == 'voice') {
      _runner._emitRenpyVoice(positional);
      return;
    }
    if (function == 'voice_sustain') {
      _runner._emitRenpyVoiceSustain();
      return;
    }
    _runner._emitRenpyApiAudio(function, positional, keywords);
  }
}

RenPyImagePlacement? _placementFromTransformBody(List<String> body) {
  final values = <String, _TransformValue>{};
  _TransformValue? alphaTarget;
  double? alphaDuration;

  for (final rawLine in body) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final alphaTween = RegExp(
      r'^linear\s+(\S+)\s+alpha\s+(.+)$',
    ).firstMatch(line);
    if (alphaTween != null) {
      final duration = _transformValue(alphaTween.group(1)!);
      final target = _transformValue(alphaTween.group(2)!);
      if (duration == null || target == null) return null;
      if (alphaTarget == null) {
        alphaDuration = duration.value;
        alphaTarget = target;
      }
      continue;
    }

    final match = RegExp(
      r'^(xpos|ypos|xanchor|yanchor|xalign|yalign|zoom|xzoom|yzoom|alpha)\s+(.+)$',
    ).firstMatch(line);
    if (match == null) {
      if (_isIgnorableAtlLine(line)) continue;
      if (values.isEmpty) return null;
      break;
    }

    final value = _transformValue(match.group(2)!);
    if (value == null) return null;
    values[match.group(1)!] = value;
  }

  if (values.isEmpty) return null;
  return RenPyImagePlacement.position(
    xpos: values['xpos']?.value,
    ypos: values['ypos']?.value,
    xanchor: values['xanchor']?.value,
    yanchor: values['yanchor']?.value,
    xalign: values['xalign']?.value,
    yalign: values['yalign']?.value,
    xposIsPixel: values['xpos']?.isPixel ?? false,
    yposIsPixel: values['ypos']?.isPixel ?? false,
    xanchorIsPixel: values['xanchor']?.isPixel ?? false,
    yanchorIsPixel: values['yanchor']?.isPixel ?? false,
    zoom: values['zoom']?.value,
    xzoom: values['xzoom']?.value,
    yzoom: values['yzoom']?.value,
    alpha: values['alpha']?.value,
    alphaTarget: alphaTarget?.value,
    alphaDuration: alphaDuration,
  );
}

bool _isIgnorableAtlLine(String line) {
  return line == 'block:' ||
      line == 'repeat' ||
      line.startsWith('pause ') ||
      RegExp(r'^on\s+\w+\s*:$').hasMatch(line);
}

_TransformValue? _transformValue(String expression) {
  final value = expression.trim();
  final number = double.tryParse(value);
  if (number == null) return null;
  final isPixel = RegExp(r'^-?\d+$').hasMatch(value);
  return _TransformValue(number, isPixel);
}

class _TransformValue {
  const _TransformValue(this.value, this.isPixel);

  final double value;
  final bool isPixel;
}

class _VariableLookup {
  const _VariableLookup(this.found, this.value);

  final bool found;
  final dynamic value;
}
