import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_audio_event.dart';
import 'renpy_dialogue_event.dart';
import 'renpy_image_event.dart';
import 'renpy_image_placement.dart';
import 'renpy_pause_event.dart';
import 'renpy_transition_event.dart';
import 'renpy_transition_resolver.dart';

class _ExecutionContext {
  final List<RenPyStatement> block;
  final int position; // where we should resume afterwards
  _ExecutionContext(this.block, this.position);
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

  /// Stack for returning from nested blocks (menus, if/else, etc.)
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

  /// Character definitions
  final Map<String, Map<String, dynamic>> _characters = {};

  RenPyDialogueEvent? _lastDialogueEvent;
  late RenPyTransitionResolver _transitionResolver;

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

  /// Error message if an error occurred
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  RenPyRunner(this.script) {
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

  dynamic _evaluateExpression(String expression) {
    final value = expression.trim();
    if (value == 'True' || value == 'true') return true;
    if (value == 'False' || value == 'false') return false;
    if (value == 'None' || value == 'null') return null;
    if (value == '[]') return <dynamic>[];

    final quoted = RegExp(r'''^["'](.*)["']$''').firstMatch(value);
    if (quoted != null) return quoted.group(1);

    final integer = int.tryParse(value);
    if (integer != null) return integer;

    final decimal = double.tryParse(value);
    if (decimal != null) return decimal;

    return value;
  }

  bool _evaluateCondition(String condition) {
    final value = condition.trim();
    if (value == 'True' || value == 'true') return true;
    if (value == 'False' || value == 'false') return false;
    if (value.startsWith('not ')) {
      return !_evaluateCondition(value.substring(4));
    }
    if (value.startsWith('!')) return !_evaluateCondition(value.substring(1));

    final variable = _variables[value];
    if (variable is bool) return variable;
    if (variable is num) return variable != 0;
    if (variable is String) return variable.isNotEmpty;
    if (variable is Iterable) return variable.isNotEmpty;
    return variable != null;
  }

  /// Start or resume execution.
  void run() {
    if (_state == RenPyRunnerState.complete ||
        _state == RenPyRunnerState.error) {
      // Reset to beginning.
      _position = 0;
      _currentBlock = script.statements;
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
        _state = RenPyRunnerState.complete;
      } else {
        _state = RenPyRunnerState.complete;
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
    } else if (stmt is RenPyPassStatement) {
      // Do nothing
      _position++;
      _executeNext();
    } else {
      // Unknown statement type, just skip it.
      print('Warning: Unknown statement type: ${stmt.runtimeType}');
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

    _emitDialogueEvent(event);

    // Wait for player input.
    _state = RenPyRunnerState.waitingForInput;
    _position++;
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
    _currentBlock = stmt.block;
    _position = 0;
    _executeNext();
  }

  /// Execute a jump statement.
  void _executeJumpStatement(RenPyJumpStatement stmt) {
    // Find the label
    final label = script.findLabel(stmt.target);
    if (label == null) {
      throw Exception('Label not found: ${stmt.target}');
    }

    // Jump to the label.
    _currentLabel = label.name;
    _currentBlock = label.block;
    _position = 0;
    _executeNext();
  }

  /// Execute a menu statement.
  void _executeMenuStatement(RenPyMenuStatement stmt) {
    final items =
        stmt.items
            .where((choice) => _evaluateCondition(choice.condition))
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
    // Resume after this statement when the branch ends.
    _stack.add(_ExecutionContext(_currentBlock, _position + 1));

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

  /// Execute a show statement.
  void _executeShowStatement(RenPyShowStatement stmt) {
    onImageEvent?.call(
      RenPyImageEvent.show(
        stmt.imageName,
        at: stmt.atExpression,
        placement: RenPyImagePlacement.parse(stmt.atExpression),
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

  /// Execute a scene statement.
  void _executeSceneStatement(RenPySceneStatement stmt) {
    onImageEvent?.call(
      RenPyImageEvent.scene(
        stmt.imageName,
        at: stmt.atExpression,
        placement: RenPyImagePlacement.parse(stmt.atExpression),
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
    onImageEvent?.call(RenPyImageEvent.hide(stmt.imageName));
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
    onTransition?.call(RenPyTransitionEvent(name, intent: intent));
  }

  /// Execute a Python statement.
  void _executePythonStatement(RenPyPythonStatement stmt) {
    final pause = _renpyPauseEvent(stmt.code);
    if (pause != null) {
      onPause?.call(pause);
      _state = RenPyRunnerState.waitingForInput;
      _position++;
      return;
    }

    // TODO: Execute Python code.
    // For now, we'll just print it and continue.
    print(
      '_executePythonStatement Unimplemented: skipping code `${stmt.code}`',
    );

    _position++;
    _executeNext();
  }

  RenPyPauseEvent? _renpyPauseEvent(String code) {
    final match = RegExp(
      r'^renpy\.pause\s*\(\s*([0-9]+(?:\.[0-9]+)?|\.[0-9]+)?\s*\)$',
    ).firstMatch(code.trim());
    if (match == null) return null;

    final duration = double.tryParse(match.group(1) ?? '');
    return RenPyPauseEvent(duration: duration);
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
      _stack.add(_ExecutionContext(_currentBlock, _position + 1));
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
    onAudio?.call(
      RenPyAudioEvent.play(
        channel: stmt.channel,
        asset: _evaluateAudioAsset(stmt.expression),
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

  void _executeReturnStatement(RenPyReturnStatement stmt) {
    if (_stack.isEmpty) {
      _state = RenPyRunnerState.complete;
      return;
    }

    final ctx = _stack.removeLast();
    _currentBlock = ctx.block;
    _position = ctx.position;
    _state = RenPyRunnerState.running;
    _executeNext();
  }

  void _executeCallStatement(RenPyCallStatement stmt) {
    final label = script.findLabel(stmt.target);
    if (label == null) {
      throw Exception('Label not found: ${stmt.target}');
    }

    _stack.add(_ExecutionContext(_currentBlock, _position + 1));
    _currentLabel = label.name;
    _currentBlock = label.block;
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
      _executeNext();
    }
  }

  /// Jump to a specific label.
  void jumpToLabel(String label) {
    final labelStmt = script.findLabel(label);
    if (labelStmt == null) {
      throw Exception('Label not found: $label');
    }

    _currentLabel = labelStmt.name;
    _currentBlock = labelStmt.block;
    _position = 0;
    _state = RenPyRunnerState.ready;
  }

  /// Reset the runner to the beginning.
  void reset() {
    _position = 0;
    _currentBlock = script.statements;
    _currentLabel = null;
    _state = RenPyRunnerState.ready;
    _errorMessage = null;
  }
}
