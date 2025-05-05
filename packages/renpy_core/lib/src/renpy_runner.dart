import 'package:renpy_parser/renpy_parser.dart';

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

/// Callback for menu events
typedef MenuCallback =
    void Function(List<String> choices, Function(int) onChoice);

/// Callback for image events
typedef ImageCallback =
    void Function(String? scene, String? show, String? hide);

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

  /// Callbacks for various events
  DialogueCallback? onDialogue;
  MenuCallback? onMenu;
  ImageCallback? onImage;

  /// Error message if an error occurred
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  RenPyRunner(this.script) {
    // Initialize with the default block of statements
    _currentBlock = script.statements;

    // Process define statements to set up characters and variables
    _processDefines();
  }

  /// Process all define statements in the script
  void _processDefines() {
    script.findStatements<RenPyDefineStatement>((stmt) => true).forEach((
      define,
    ) {
      if (define.expression.contains('Character(')) {
        // Parse character definition
        _parseCharacter(define.name, define.expression);
      } else {
        // Regular variable
        _variables[define.name] = define.expression;
      }
    });
  }

  /// Parse a character definition.
  void _parseCharacter(String name, String expression) {
    // This is a simplified parser for character definitions.

    final params = <String, dynamic>{};

    // Extract the character name (first parameter to Character()).
    final nameMatch = RegExp(
      r'''Character\s*\(\s*["\']([^"\']*)["\']''',
    ).firstMatch(expression);
    if (nameMatch != null) {
      params['name'] = nameMatch.group(1);
    }

    // Extract other parameters like color.
    final colorMatch = RegExp(
      r''''color\s*=\s*["\']([^"\']*)["\']''',
    ).firstMatch(expression);
    if (colorMatch != null) {
      params['color'] = colorMatch.group(1);
    }

    _characters[name] = params;
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
    // ❶  finished the current block?
    if (_position >= _currentBlock.length) {
      if (_stack.isNotEmpty) {
        // Pop back to the parent context (e.g., we’re done with a menu branch)
        final ctx = _stack.removeLast();
        _currentBlock = ctx.block;
        _position     = ctx.position;
        return _executeNext();        // continue immediately
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
    } else if (stmt is RenPyWithStatement) {
      _executeWithStatement(stmt);
    } else if (stmt is RenPyPythonStatement) {
      _executePythonStatement(stmt);
    } else if (stmt is RenPyDefineStatement) {
      _executeDefineStatement(stmt);
    } else if (stmt is RenPyIfStatement) {
      _executeIfStatement(stmt);
    }
    else if (stmt is RenPyPlayStatement) { _executePlayStatement(stmt); }else if (stmt is RenPyPassStatement) {
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
    // Resolve character name if it's a defined character.
    String? displayName;
    if (stmt.character != null && _characters.containsKey(stmt.character)) {
      displayName = _characters[stmt.character]!['name'] as String?;
    } else {
      displayName = stmt.character;
    }

    // Display the dialogue.
    if (onDialogue != null) {
      onDialogue!(displayName, stmt.text ?? '');
    }

    // Wait for player input.
    _state = RenPyRunnerState.waitingForInput;
    _position++;
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
    // No callback?  Fall back to first choice.
    if (onMenu == null) {
      _executeMenuChoice(stmt.items.first);
      return;
    }

    final choices = stmt.items.map((c) => c.text).toList();
    onMenu!(choices, (index) => _executeMenuChoice(stmt.items[index]));

    // Wait for UI / test harness.
    _state = RenPyRunnerState.waitingForInput;
  }

  /// Execute a menu choice.
  void _executeMenuChoice(MenuChoice choice) {
    // Resume after this statement when the branch ends.
    _stack.add(_ExecutionContext(_currentBlock, _position + 1));

    if (choice.block.isEmpty) {
      // Nothing inside → behave like “pass”.
      _currentBlock = _stack.removeLast().block;
      _position++; // Resume after menu statement.
      return _executeNext();
    }

    _currentBlock = choice.block;
    _position     = 0;
    _state        = RenPyRunnerState.running; // We just answered – keep going.
    _executeNext();
  }

  /// Execute a show statement.
  void _executeShowStatement(RenPyShowStatement stmt) {
    if (onImage != null) {
      onImage!(null, stmt.imageName, null);
    }

    _position++;
    _executeNext();
  }

  /// Execute a scene statement.
  void _executeSceneStatement(RenPySceneStatement stmt) {
    if (onImage != null) {
      onImage!(stmt.imageName, null, null);
    }

    _position++;
    _executeNext();
  }

  /// Execute a with statement.
  void _executeWithStatement(RenPyWithStatement stmt) {
    // In a real implementation, this would handle transitions.

    _position++;
    _executeNext();
  }

  /// Execute a Python statement.
  void _executePythonStatement(RenPyPythonStatement stmt) {
    // TODO: Execute Python code.
    // For now, we'll just print it and continue.
    print(
      '_executePythonStatement Unimplemented: skipping code `${stmt.code}`',
    );

    _position++;
    _executeNext();
  }

  /// Execute a define statement.
  void _executeDefineStatement(RenPyDefineStatement stmt) {
    // Most define statements are handled during initialization but we still need to handle runtime definitions.

    if (stmt.expression.contains('Character(')) {
      _parseCharacter(stmt.name, stmt.expression);
    } else {
      _variables[stmt.name] = stmt.expression;
    }

    _position++;
    _executeNext();
  }

  /// Execute an if statement
  void _executeIfStatement(RenPyIfStatement stmt) {
    // TODO: Evaluate the condition.
    // For now, we'll just execute the first block.
    print('_executeIfStatement Unimplemented: choosing first block.');

    if (stmt.entries.isNotEmpty) {
      _currentBlock = stmt.entries[0].block;
      _position = 0;
      _executeNext();
    } else {
      _position++;
      _executeNext();
    }
  }

  /// Execute a play statement.
  ///
  /// Plays a sound.  This is a placeholder for actual sound handling which will
  /// be implemented later. TODO
  void _executePlayStatement(RenPyPlayStatement stmt) {
    // TODO: Handle sound playing.
    print('[Play ${stmt.channel}] ${stmt.expression}');
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
