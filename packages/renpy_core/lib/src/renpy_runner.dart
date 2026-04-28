import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_audio_event.dart';
import 'renpy_diagnostic.dart';
import 'renpy_dialogue_event.dart';
import 'renpy_expression_evaluator.dart';
import 'renpy_image_event.dart';
import 'renpy_image_placement.dart';
import 'renpy_pause_event.dart';
import 'renpy_persistent_store.dart';
import 'renpy_transition_event.dart';
import 'renpy_transition_intent.dart';
import 'renpy_transition_resolver.dart';
import 'renpy_runner_snapshot.dart';

enum _ExecutionContextKind { block, labelFallthrough, call }

class _ExecutionContext {
  _ExecutionContext(this.block, this.position, this.kind);

  final List<RenPyStatement> block;
  final int position; // where we should resume afterwards
  final _ExecutionContextKind kind;
}

class _LabelContext {
  const _LabelContext(this.label, this.parentBlock, this.index);

  final RenPyLabelStatement label;
  final List<RenPyStatement> parentBlock;
  final int index;
}

class _PendingDialogue {
  const _PendingDialogue(this.event, this.searchStart);

  final RenPyDialogueEvent event;
  final int searchStart;
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

  /// Ren'Py persistent namespace values assigned during this run.
  final Map<String, dynamic> _persistent;

  /// Optional backing store for persistent namespace values.
  final RenPyPersistentStore? _persistentStore;

  Map<String, dynamic> get persistent => Map.unmodifiable(_persistent);

  /// Character definitions
  final Map<String, Map<String, dynamic>> _characters = {};

  RenPyDialogueEvent? _lastDialogueEvent;
  _PendingDialogue? _pendingDialogue;
  late RenPyTransitionResolver _transitionResolver;
  final Map<String, RenPyImagePlacement> _transformPlacements = {};

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
  RenPyDiagnosticCallback? onDiagnostic;

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
    _transitionResolver = RenPyTransitionResolver.fromScript(script);

    // Process define statements to set up characters and variables
    _processDefines();
  }

  /// Process all define statements in the script
  void _processDefines() {
    void process(List<RenPyStatement> statements) {
      for (final statement in statements) {
        if (statement is RenPyDefineStatement) {
          _applyDefinition(statement.name, statement.expression);
        } else if (statement is RenPyDefaultStatement) {
          _variables.putIfAbsent(
            statement.name,
            () => _evaluateExpression(statement.expression),
          );
        } else if (statement is RenPyPythonStatement) {
          _applyAudioChannelRegistration(statement.code);
        } else if (statement is RenPyTransformStatement) {
          _applyTransformStatement(statement);
        } else if (statement is RenPyInitStatement) {
          process(statement.block);
        }
      }
    }

    process(script.statements);
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
      _variables[name] = _evaluateExpression(expression);
    }
  }

  void _applyTransformStatement(RenPyTransformStatement statement) {
    final name = _transformName(statement.signature);
    if (name == null) return;
    final placement = _placementFromTransformBody(statement.body);
    if (placement != null) {
      _transformPlacements[name] = placement;
    }
  }

  String? _transformName(String signature) {
    final match = RegExp(r'^([A-Za-z_]\w*)').firstMatch(signature.trim());
    return match?.group(1);
  }

  dynamic _evaluateExpression(String expression) {
    final value = expression.trim();
    if (value == 'True' || value == 'true') return true;
    if (value == 'False' || value == 'false') return false;
    if (value == 'None' || value == 'null') return null;
    if (RegExp(r'^\[\s*\]$').hasMatch(value)) return <dynamic>[];

    final imagemapResult = _renpyImagemapResult(value);
    if (imagemapResult != null) return imagemapResult;

    final quoted = RegExp(r'''^["'](.*)["']$''').firstMatch(value);
    if (quoted != null) return quoted.group(1);

    final integer = int.tryParse(value);
    if (integer != null) return integer;

    final decimal = double.tryParse(value);
    if (decimal != null) return decimal;

    return value;
  }

  bool _evaluateCondition(String condition) {
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
      // Reset to beginning.
      _position = 0;
      _currentBlock = script.statements;
      _pendingDialogue = null;
      _state = RenPyRunnerState.ready;
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
        return _executeNext(); // continue immediately
      }

      // otherwise original end-of-script behaviour:
      if (_currentLabel != null) {
        _currentLabel = null;
        _complete();
      } else {
        _complete();
      }
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
    } else if (stmt is RenPyPlayStatement) {
      _executePlayStatement(stmt);
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

    _position++;
    if (_hasNoWaitTag(event.text)) {
      _emitDialogueEvent(event);
      _executeNext();
      return;
    }

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

    // Wait for player input.
    _state = RenPyRunnerState.waitingForInput;
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
    final context = _findLabelContext(stmt.target);
    if (context == null) {
      throw Exception('Label not found: ${stmt.target}');
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
    _variables[setVariable] = <String>[choice];
  }

  /// Execute a show statement.
  void _executeShowStatement(RenPyShowStatement stmt) {
    final placement = _placementFor(stmt.atExpression);
    _diagnosePlacement(placement);
    onImageEvent?.call(
      RenPyImageEvent.show(
        stmt.imageName,
        at: stmt.atExpression,
        placement: placement,
        onLayer: stmt.onLayerExpression,
        zOrder: _parseZOrder(stmt.zOrderExpression),
        behind: stmt.behindExpression,
        displayableText: stmt.displayableText,
      ),
    );
    if (onImage != null) {
      onImage!(null, stmt.imageName, null);
    }
    _emitInlineTransition(stmt.withExpression);

    _position++;
    _executeNext();
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

    if (_isRecognizedNoOpPythonCall(stmt.code)) {
      _position++;
      _executeNext();
      return;
    }

    // TODO: Execute Python code.
    // For now, we'll just print it and continue.
    print(
      '_executePythonStatement Unimplemented: skipping code `${stmt.code}`',
    );
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
    onDiagnostic?.call(diagnostic);
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
    final match = RegExp(
      r'^([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*([+\-])=\s*(.+)$',
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
    final value = _applyPythonOperator(left, assignment.operator, right);
    _setVariable(assignment.name, value);
  }

  dynamic _defaultAugmentedValue(dynamic right) {
    if (right is num) return 0;
    if (right is String) return '';
    return null;
  }

  dynamic _applyPythonOperator(dynamic left, String operator, dynamic right) {
    return switch (operator) {
      '+' when left is num && right is num => left + right,
      '+' when left is String && right is String => left + right,
      '-' when left is num && right is num => left - right,
      _ => right,
    };
  }

  void _setVariable(String name, dynamic value) {
    final persistentField = _persistentFieldName(name);
    if (persistentField != null) {
      _persistent[persistentField] = value;
      _flushPersistent();
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
    _variables.putIfAbsent(
      stmt.name,
      () => _evaluateExpression(stmt.expression),
    );

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
    onAudio?.call(
      RenPyAudioEvent.stop(channel: stmt.channel, fadeout: stmt.fadeout),
    );
    _position++;
    _executeNext();
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
        _state = RenPyRunnerState.running;
        _executeNext();
        return;
      }
    }

    _complete();
  }

  void _executeCallStatement(RenPyCallStatement stmt) {
    final context = _findLabelContext(stmt.target);
    if (context == null) {
      throw Exception('Label not found: ${stmt.target}');
    }

    _stack.add(
      _ExecutionContext(
        _currentBlock,
        _position + 1,
        _ExecutionContextKind.call,
      ),
    );
    _currentLabel = context.label.name;
    _currentBlock = context.label.block;
    _position = 0;
    _executeNext();
  }

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
        snapshot.stack.map(
          (frame) => _ExecutionContext(
            _blockForPath(frame.blockPath),
            frame.position,
            _contextKindFor(frame.kind),
          ),
        ),
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
    _pendingDialogue = null;
    _prepareLabelContext(context);
    _state = RenPyRunnerState.ready;
  }

  _LabelContext? _findLabelContext(String name) {
    _LabelContext? search(List<RenPyStatement> block) {
      for (var index = 0; index < block.length; index += 1) {
        final statement = block[index];
        if (statement is RenPyLabelStatement && statement.name == name) {
          return _LabelContext(statement, block, index);
        }

        if (statement is RenPyBlockStatement) {
          final nested = search(statement.block);
          if (nested != null) return nested;
        }
      }
      return null;
    }

    return search(script.statements);
  }

  void _prepareLabelContext(_LabelContext context) {
    _currentLabel = context.label.name;
    _currentBlock = context.label.block;
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
    while (_stack.isNotEmpty &&
        _stack.last.kind != _ExecutionContextKind.call) {
      _stack.removeLast();
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
  void reset() {
    _stack.clear();
    _pendingDialogue = null;
    _position = 0;
    _currentBlock = script.statements;
    _currentLabel = null;
    _state = RenPyRunnerState.ready;
    _errorMessage = null;
  }

  void _complete() {
    _state = RenPyRunnerState.complete;
    _flushPersistent();
  }

  void _flushPersistent() {
    _persistentStore?.save(_persistent);
  }
}

RenPyImagePlacement? _placementFromTransformBody(List<String> body) {
  final values = <String, _TransformValue>{};
  for (final rawLine in body) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final match = RegExp(
      r'^(xpos|ypos|xanchor|yanchor|xalign|yalign|zoom|xzoom|yzoom|alpha)\s+(.+)$',
    ).firstMatch(line);
    if (match == null) {
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
  );
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
