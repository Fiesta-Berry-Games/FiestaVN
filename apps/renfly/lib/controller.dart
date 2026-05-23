import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:renpy_core/renpy_core.dart';

/// Public, minimal information describing what the player should currently see.
sealed class RenPyGameStatus {}

/// Idle → waiting for the app to load a script, nothing on screen yet.
final class RenPyIdle extends RenPyGameStatus {}

/// A line of dialogue (optionally attributed to a character).
final class RenPyDialogue extends RenPyGameStatus {
  RenPyDialogue(this.character, this.text);
  final String? character;
  final String text;
}

/// A choice menu.  UI must call [onChoice] with the index the user picked.
final class RenPyMenu extends RenPyGameStatus {
  RenPyMenu(this.choices, this.onChoice, {this.caption});
  final List<String> choices;
  final void Function(int) onChoice;
  final String? caption;
}

/// Emitted when a `scene`, `show`, or `hide` image command is encountered.
final class RenPyImageChange extends RenPyGameStatus {
  RenPyImageChange({
    this.scene,
    this.show,
    this.hide,
    this.sceneAsset,
    this.showAsset,
  });
  final String? scene;
  final String? show;
  final String? hide;
  final String? sceneAsset;
  final String? showAsset;
}

/// The game finished running normally.
final class RenPyComplete extends RenPyGameStatus {}

/// The runner encountered an unrecoverable error.
final class RenPyError extends RenPyGameStatus {
  RenPyError(this.message);
  final String message;
}

/// Drives [RenPyRunner] and turns callbacks into [ValueNotifier] updates.
class RenPyFlutterController extends ValueNotifier<RenPyGameStatus> {
  RenPyFlutterController({this.onComplete}) : super(RenPyIdle());

  final VoidCallback? onComplete;

  RenPyRunner? _runner;
  StreamSubscription? _ticker; // Nullable so we can dispose/re-create.
  String? _gameRoot;
  Set<String> _availableAssets = {};
  Map<String, String> _imageAliases = {};

  /// Loads a `.rpy` script (raw source string) and immediately jumps
  /// to the `start` label if it exists.  Calling [load] again cleanly
  /// restarts the controller with the new script.
  void load(
    String source, {
    String filename = '<memory>',
    String? gameRoot,
    Set<String> availableAssets = const {},
  }) {
    debugPrint('Loading RenPy script...');
    _ticker?.cancel();
    _runner = null;
    value = RenPyIdle();
    _gameRoot = gameRoot;
    _availableAssets = availableAssets;

    final parser = RenPyParser();
    final result = parser.parse(source, filename);
    _imageAliases = _buildImageAliases(result.script);

    debugPrint(
      'Parsed script with ${result.script.statements.length} statements',
    );

    final runner =
        RenPyRunner(result.script)
          ..onDialogue = _onDialogue
          ..onMenu = _onMenu
          ..onImage = _onImage;
    _runner = runner;

    if (result.script.findLabel('start') != null) {
      debugPrint('Found start label, jumping to it');
      runner.jumpToLabel('start');
    } else {
      debugPrint('No start label found');
    }

    _startTicker();
    debugPrint('Starting initial execution...');
    runner.run(); // Start first run-loop cycle.
  }

  /// Player pressed "next".
  void continueGame() {
    final r = _runner;
    if (r == null) return;
    if (r.state == RenPyRunnerState.waitingForInput) {
      debugPrint('Continuing game execution...');
      r.continueExecution();
      _ticker?.resume();
    }
  }

  void _startTicker() {
    // (re)create a 1 ms timer-based ticker that drives the runner forward.
    _ticker = Stream.periodic(const Duration(milliseconds: 1)).listen((_) {
      final r = _runner;
      if (r == null) return;

      switch (r.state) {
        case RenPyRunnerState.waitingForInput:
          _ticker?.pause(); // Wait for player / menu.
          break;
        case RenPyRunnerState.complete:
          debugPrint('Script execution complete');
          value = RenPyComplete();
          _ticker?.cancel();
          onComplete?.call();
          break;
        case RenPyRunnerState.error:
          debugPrint('Script execution error: ${r.errorMessage}');
          value = RenPyError(r.errorMessage ?? 'Unknown error');
          _ticker?.cancel();
          break;
        default:
          r.continueExecution(); // Keep crunching through script.
      }
    });
  }

  void _onDialogue(String? character, String text) {
    debugPrint('Dialogue: ${character ?? "Narrator"}: $text');
    _ticker?.pause(); // Freeze on dialogue.
    value = RenPyDialogue(character, text);
  }

  void _onMenu(
    List<String> choices,
    void Function(int index) onChoice,
    String? caption,
  ) {
    debugPrint('Menu with choices: $choices');
    // Called for every menu, including nested ones.
    _ticker?.pause();
    value = RenPyMenu(choices, (i) {
      debugPrint('Menu choice selected: ${choices[i]}');
      onChoice(i); // Notify runner.
      _ticker?.resume(); // Resume execution afterwards.
    }, caption: caption);
  }

  void _onImage(String? scene, String? show, String? hide) {
    debugPrint('Image command - scene: $scene, show: $show, hide: $hide');
    // _ticker?.pause(); // Can be used to allow a reaction before continuing.
    value = RenPyImageChange(
      scene: scene,
      show: show,
      hide: hide,
      sceneAsset: _resolveImageAsset(scene),
      showAsset: _resolveImageAsset(show),
    );
  }

  Map<String, String> _buildImageAliases(RenPyScript script) {
    final aliases = <String, String>{};
    for (final image in script.findStatements<RenPyImageStatement>(
      (_) => true,
    )) {
      final expression = image.expression.trim();
      final imageCall = RegExp(
        r'''Image\s*\(\s*["']([^"']+)["']\s*\)''',
      ).firstMatch(expression);
      final quoted = RegExp(r'''^["']([^"']+)["']$''').firstMatch(expression);
      aliases[image.name] =
          imageCall?.group(1) ?? quoted?.group(1) ?? expression;
    }
    return aliases;
  }

  String? _resolveImageAsset(String? imageName) {
    final root = _gameRoot;
    if (imageName == null || root == null) return null;
    if (imageName == 'black') return null;

    final clean = imageName.split('#').first.trim();
    final alias = _imageAliases[clean];
    final candidates = <String>[];

    void addCandidate(String relativePath) {
      final normalized = relativePath.replaceAll(RegExp(r'^/+'), '');
      if (normalized.startsWith('assets/')) {
        candidates.add(normalized);
      } else {
        candidates.add('$root/$normalized');
        candidates.add('$root/images/$normalized');
      }
    }

    if (alias != null) {
      addCandidate(alias);
    }

    final hasExtension = RegExp(
      r'\.(png|jpg|jpeg|webp|gif)$',
      caseSensitive: false,
    ).hasMatch(clean);
    if (hasExtension) {
      addCandidate(clean);
    } else {
      for (final extension in const ['png', 'jpg', 'jpeg', 'webp', 'gif']) {
        addCandidate('$clean.$extension');
        addCandidate('${clean.replaceAll(' ', '_')}.$extension');
      }
    }

    for (final candidate in candidates) {
      if (_availableAssets.contains(candidate)) return candidate;
    }

    return candidates.isNotEmpty ? candidates.first : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
