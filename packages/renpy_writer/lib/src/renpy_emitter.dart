import 'package:renpy_parser/renpy_parser.dart';

/// Serializes a parsed [RenPyScript] AST (from `package:renpy_parser`) back to
/// valid `.rpy` script text.
///
/// The emitter is designed as the inverse of [RenPyParser]: the emitted text
/// re-parses to an equivalent AST, and emission is a fixpoint - parsing the
/// emitted text and emitting it again yields the exact same text.
///
/// Notable normalizations (all stable under re-parsing):
///
/// * `$ name = expression` lines re-emit as `define name = expression`,
///   because the parser already classifies them as [RenPyDefineStatement].
/// * `python early:` blocks re-emit as `init python:` (the parser only keeps
///   an `isInit` flag on [RenPyPythonStatement]).
/// * Empty statement blocks gain an explicit `pass` line so the output
///   re-parses cleanly.
class RenPyEmitter {
  /// Creates an emitter that indents nested blocks with [indent].
  const RenPyEmitter({this.indent = '    '});

  /// The string emitted for one level of indentation.
  final String indent;

  static final RegExp _identifierPattern = RegExp(r'^[A-Za-z_]\w*$');

  /// Mirrors the parser's `$ name = expression` -> define classification: any
  /// single-line python code matching this must not be emitted in `$` form.
  static final RegExp _assignmentPattern = RegExp(
    r'^[a-zA-Z_]\w*\s*=\s*.+$',
    dotAll: true,
  );

  /// Displayable keywords recognized by the screen body parser. A screen
  /// property whose name collides with one of these cannot be emitted as a
  /// standalone body line (it would re-parse as a child displayable), so it is
  /// kept inline on the header line instead.
  static const Set<String> _displayableKeywords = <String>{
    'vbox',
    'hbox',
    'fixed',
    'frame',
    'window',
    'grid',
    'side',
    'text',
    'label',
    'textbutton',
    'imagebutton',
    'button',
    'bar',
    'vbar',
    'viewport',
    'vpgrid',
    'null',
    'add',
    'key',
    'timer',
    'input',
    'image',
    'imagemap',
    'hotspot',
    'hotbar',
    'mousearea',
    'drag',
    'draggroup',
  };

  /// Screen-language control words that may not begin a standalone property
  /// line (the screen body parser would interpret them as control flow).
  static const Set<String> _screenControlWords = <String>{
    'if',
    'elif',
    'else',
    'for',
    'use',
    'has',
    'transclude',
    'python',
    'on',
    'pass',
  };

  /// Emits a full `.rpy` document: every top-level statement in [script]
  /// joined by newlines, with a trailing newline.
  String emitScript(RenPyScript script) {
    final buffer = StringBuffer();
    for (final statement in script.statements) {
      buffer.writeln(emitStatement(statement));
    }
    return buffer.toString();
  }

  /// Emits a single [statement] (including its nested blocks) indented by
  /// [depth] levels. The result contains no trailing newline.
  String emitStatement(RenPyStatement statement, [int depth = 0]) {
    final lines = <String>[];
    _statement(statement, depth, lines);
    return lines.join('\n');
  }

  // --------------------------------------------------------------------
  // Statement dispatch
  // --------------------------------------------------------------------

  void _statement(RenPyStatement statement, int depth, List<String> lines) {
    if (statement is RenPySayStatement) {
      lines.add('${_pad(depth)}${_say(statement)}');
    } else if (statement is RenPyLabelStatement) {
      _label(statement, depth, lines);
    } else if (statement is RenPyMenuStatement) {
      _menu(statement, depth, lines);
    } else if (statement is RenPyJumpStatement) {
      final keyword = statement.isExpression ? 'jump expression' : 'jump';
      lines.add('${_pad(depth)}$keyword ${statement.target}');
    } else if (statement is RenPyCallStatement) {
      lines.add('${_pad(depth)}${_call(statement)}');
    } else if (statement is RenPyShowStatement) {
      lines.add('${_pad(depth)}${_show(statement)}');
    } else if (statement is RenPySceneStatement) {
      lines.add('${_pad(depth)}${_scene(statement)}');
    } else if (statement is RenPyHideStatement) {
      lines.add('${_pad(depth)}${_hide(statement)}');
    } else if (statement is RenPyWithStatement) {
      lines.add('${_pad(depth)}with ${statement.transition}');
    } else if (statement is RenPyPythonStatement) {
      _python(statement, depth, lines);
    } else if (statement is RenPyDefineStatement) {
      lines.add(
        '${_pad(depth)}define ${statement.name} = ${statement.expression}',
      );
    } else if (statement is RenPyDefaultStatement) {
      lines.add(
        '${_pad(depth)}default ${statement.name} = ${statement.expression}',
      );
    } else if (statement is RenPyIfStatement) {
      _if(statement, depth, lines);
    } else if (statement is RenPyWhileStatement) {
      lines.add('${_pad(depth)}while ${statement.condition}:');
      _block(statement.block, depth + 1, lines);
    } else if (statement is RenPyForStatement) {
      lines.add(
        '${_pad(depth)}for ${statement.variable} in ${statement.iterable}:',
      );
      _block(statement.block, depth + 1, lines);
    } else if (statement is RenPyLoopControlStatement) {
      final keyword = statement.action == RenPyLoopControlAction.breakLoop
          ? 'break'
          : 'continue';
      lines.add('${_pad(depth)}$keyword');
    } else if (statement is RenPyPassStatement) {
      lines.add('${_pad(depth)}pass');
    } else if (statement is RenPyReturnStatement) {
      final expression =
          statement.expression == null ? '' : ' ${statement.expression}';
      lines.add('${_pad(depth)}return$expression');
    } else if (statement is RenPyNvlStatement) {
      // RenPyNvlAction.clear is the only action.
      lines.add('${_pad(depth)}nvl clear');
    } else if (statement is RenPyImageStatement) {
      _image(statement, depth, lines);
    } else if (statement is RenPyWindowStatement) {
      final transition =
          statement.transition == null ? '' : ' ${statement.transition}';
      lines.add('${_pad(depth)}window ${statement.action.name}$transition');
    } else if (statement is RenPyPauseStatement) {
      final duration =
          statement.duration == null ? '' : ' ${statement.duration}';
      lines.add('${_pad(depth)}pause$duration');
    } else if (statement is RenPyPlayStatement) {
      lines.add(
        '${_pad(depth)}play ${statement.channel} ${statement.expression}',
      );
    } else if (statement is RenPyQueueStatement) {
      lines.add(
        '${_pad(depth)}queue ${statement.channel} ${statement.expression}',
      );
    } else if (statement is RenPyVoiceStatement) {
      final expression =
          statement.expression.isEmpty ? '' : ' ${statement.expression}';
      lines.add('${_pad(depth)}voice$expression');
    } else if (statement is RenPyStopStatement) {
      final fadeout =
          statement.fadeout == null ? '' : ' fadeout ${statement.fadeout}';
      lines.add('${_pad(depth)}stop ${statement.channel}$fadeout');
    } else if (statement is RenPyInitOffsetStatement) {
      lines.add('${_pad(depth)}init offset = ${statement.offset}');
    } else if (statement is RenPyInitStatement) {
      _init(statement, depth, lines);
    } else if (statement is RenPyScreenStatement) {
      _screen(statement, depth, lines);
    } else if (statement is RenPyStyleStatement) {
      _style(statement, depth, lines);
    } else if (statement is RenPyTransformStatement) {
      _transform(statement, depth, lines);
    } else if (statement is RenPyLayeredImageStatement) {
      _layeredImage(statement, depth, lines);
    } else if (statement is RenPyGenericStatement) {
      lines.add('${_pad(depth)}${statement.text}');
    } else {
      throw UnsupportedError(
        'RenPyEmitter cannot emit ${statement.runtimeType}',
      );
    }
  }

  // --------------------------------------------------------------------
  // Simple statements
  // --------------------------------------------------------------------

  String _say(RenPySayStatement statement) {
    final text = _quote(statement.text ?? '');
    final character = statement.character;
    if (character == null) return text;
    final speaker = _identifierPattern.hasMatch(character)
        ? character
        : '"$character"';
    return [
      speaker,
      ...statement.attributes,
      if (statement.temporaryAttributes.isNotEmpty) ...[
        '@',
        ...statement.temporaryAttributes,
      ],
      text,
    ].join(' ');
  }

  String _call(RenPyCallStatement statement) {
    if (statement.isScreen) {
      final args =
          statement.screenArgs == null ? '' : '(${statement.screenArgs})';
      return 'call screen ${statement.screenName}$args';
    }
    if (statement.isExpression) {
      return 'call expression ${statement.target}';
    }
    final args = statement.callArgs == null ? '' : '(${statement.callArgs})';
    return 'call ${statement.target}$args';
  }

  String _show(RenPyShowStatement statement) {
    final buffer = StringBuffer();
    if (statement.displayableText != null) {
      buffer.write('show text ${_quote(statement.displayableText!)}');
      if (statement.imageName != 'text') {
        buffer.write(' as ${statement.imageName}');
      }
    } else {
      buffer.write('show ${statement.imageName}');
    }
    _writeClause(buffer, 'at', statement.atExpression);
    _writeClause(buffer, 'behind', statement.behindExpression);
    _writeClause(buffer, 'onlayer', statement.onLayerExpression);
    _writeClause(buffer, 'zorder', statement.zOrderExpression);
    _writeClause(buffer, 'with', statement.withExpression);
    return buffer.toString();
  }

  String _scene(RenPySceneStatement statement) {
    if (statement.imageName == null) return 'scene';
    final buffer = StringBuffer('scene ${statement.imageName}');
    _writeClause(buffer, 'at', statement.atExpression);
    _writeClause(buffer, 'onlayer', statement.onLayerExpression);
    _writeClause(buffer, 'zorder', statement.zOrderExpression);
    _writeClause(buffer, 'with', statement.withExpression);
    return buffer.toString();
  }

  String _hide(RenPyHideStatement statement) {
    final buffer = StringBuffer('hide ${statement.imageName}');
    _writeClause(buffer, 'onlayer', statement.onLayerExpression);
    _writeClause(buffer, 'with', statement.withExpression);
    return buffer.toString();
  }

  void _writeClause(StringBuffer buffer, String keyword, String? value) {
    if (value != null) buffer.write(' $keyword $value');
  }

  // --------------------------------------------------------------------
  // Block statements
  // --------------------------------------------------------------------

  void _label(RenPyLabelStatement statement, int depth, List<String> lines) {
    final parameters = statement.parameters.isEmpty
        ? ''
        : '(${statement.parameters.map(_parameter).join(', ')})';
    lines.add('${_pad(depth)}label ${statement.name}$parameters:');
    _block(statement.block, depth + 1, lines);
  }

  String _parameter(RenPyParameter parameter) {
    return parameter.defaultExpression == null
        ? parameter.name
        : '${parameter.name}=${parameter.defaultExpression}';
  }

  void _menu(RenPyMenuStatement statement, int depth, List<String> lines) {
    final name = statement.name == null ? '' : ' ${statement.name}';
    lines.add('${_pad(depth)}menu$name:');
    if (statement.caption != null) {
      lines.add('${_pad(depth + 1)}${_quote(statement.caption!)}');
    }
    if (statement.setVariable != null) {
      lines.add('${_pad(depth + 1)}set ${statement.setVariable}');
    }
    for (final choice in statement.items) {
      final condition =
          choice.condition == 'True' ? '' : ' if ${choice.condition}';
      lines.add('${_pad(depth + 1)}${_quote(choice.text)}$condition:');
      _block(choice.block, depth + 2, lines);
    }
  }

  void _if(RenPyIfStatement statement, int depth, List<String> lines) {
    for (var i = 0; i < statement.entries.length; i += 1) {
      final entry = statement.entries[i];
      final String header;
      if (i == 0) {
        header = 'if ${entry.condition}:';
      } else if (entry.condition == 'True' &&
          i == statement.entries.length - 1) {
        header = 'else:';
      } else {
        header = 'elif ${entry.condition}:';
      }
      lines.add('${_pad(depth)}$header');
      _block(entry.block, depth + 1, lines);
    }
  }

  void _python(RenPyPythonStatement statement, int depth, List<String> lines) {
    var code = statement.code;
    if (code.trim().isEmpty) code = 'pass';
    if (statement.isInit) {
      // The parser produces a bare init python statement only for
      // `python early:`; `init python:` re-parses as a RenPyInitStatement
      // wrapping this, which emits the same text again (fixpoint).
      lines.add('${_pad(depth)}init python:');
      _rawLines(code, depth + 1, lines);
      return;
    }
    // A plain `name = value` line must not be emitted as `$ name = value`:
    // the parser classifies that shape as a define statement.
    if (!code.contains('\n') && !_assignmentPattern.hasMatch(code)) {
      lines.add('${_pad(depth)}\$ $code');
      return;
    }
    lines.add('${_pad(depth)}python:');
    _rawLines(code, depth + 1, lines);
  }

  void _init(RenPyInitStatement statement, int depth, List<String> lines) {
    final priority =
        statement.priority == 0 ? '' : ' ${statement.priority}';
    if (statement.isPython &&
        statement.block.length == 1 &&
        statement.block.first is RenPyPythonStatement) {
      final python = statement.block.first as RenPyPythonStatement;
      final code = python.code.trim().isEmpty ? 'pass' : python.code;
      lines.add('${_pad(depth)}init$priority python:');
      _rawLines(code, depth + 1, lines);
      return;
    }
    lines.add('${_pad(depth)}init$priority:');
    _block(statement.block, depth + 1, lines);
  }

  void _image(RenPyImageStatement statement, int depth, List<String> lines) {
    if (statement.expression.isNotEmpty) {
      lines.add(
        '${_pad(depth)}image ${statement.name} = ${statement.expression}',
      );
      return;
    }
    lines.add('${_pad(depth)}image ${statement.name}:');
    for (final line in statement.body) {
      lines.add('${_pad(depth + 1)}$line');
    }
  }

  void _transform(
    RenPyTransformStatement statement,
    int depth,
    List<String> lines,
  ) {
    lines.add('${_pad(depth)}transform ${statement.signature}:');
    // Emit the raw body fallback verbatim; each line already carries its
    // indentation relative to the first body line.
    for (final line in statement.body) {
      lines.add('${_pad(depth + 1)}$line');
    }
  }

  void _style(RenPyStyleStatement statement, int depth, List<String> lines) {
    final properties = statement.style?.properties ?? const <String, String>{};
    if (properties.isEmpty) {
      lines.add('${_pad(depth)}style ${statement.declaration}');
      return;
    }
    lines.add('${_pad(depth)}style ${statement.declaration}:');
    properties.forEach((key, value) {
      lines.add('${_pad(depth + 1)}${value.isEmpty ? key : '$key $value'}');
    });
  }

  // --------------------------------------------------------------------
  // Screens
  // --------------------------------------------------------------------

  void _screen(RenPyScreenStatement statement, int depth, List<String> lines) {
    lines.add('${_pad(depth)}screen ${statement.signature}:');
    for (final child in statement.children) {
      _screenNode(child, depth + 1, lines);
    }
  }

  void _screenNode(RenPyScreenNode node, int depth, List<String> lines) {
    switch (node.nodeKind) {
      case RenPyScreenNodeKind.displayable:
        _screenDisplayable(node, depth, lines);
      case RenPyScreenNodeKind.ifChain:
        for (var i = 0; i < node.branches.length; i += 1) {
          final branch = node.branches[i];
          final String header;
          if (i == 0) {
            header = 'if ${branch.condition}:';
          } else if (branch.condition == 'True' &&
              i == node.branches.length - 1) {
            header = 'else:';
          } else {
            header = 'elif ${branch.condition}:';
          }
          lines.add('${_pad(depth)}$header');
          for (final child in branch.children) {
            _screenNode(child, depth + 1, lines);
          }
        }
      case RenPyScreenNodeKind.forLoop:
        lines.add(
          '${_pad(depth)}for ${node.forTarget} in ${node.forIterable}:',
        );
        for (final child in node.children) {
          _screenNode(child, depth + 1, lines);
        }
      case RenPyScreenNodeKind.python:
        lines.add('${_pad(depth)}\$ ${node.pythonCode}');
      case RenPyScreenNodeKind.pythonBlock:
        lines.add('${_pad(depth)}python:');
        final code = node.pythonCode ?? '';
        if (code.isNotEmpty) _rawLines(code, depth + 1, lines);
      case RenPyScreenNodeKind.on:
        lines.add('${_pad(depth)}on ${node.event}:');
        for (final child in node.children) {
          _screenNode(child, depth + 1, lines);
        }
      case RenPyScreenNodeKind.use:
        final target = node.positionalArgs.isEmpty
            ? ''
            : ' ${node.positionalArgs.first}';
        if (node.children.isEmpty) {
          lines.add('${_pad(depth)}use$target');
        } else {
          lines.add('${_pad(depth)}use$target:');
          for (final child in node.children) {
            _screenNode(child, depth + 1, lines);
          }
        }
      case RenPyScreenNodeKind.transclude:
        lines.add('${_pad(depth)}transclude');
      case RenPyScreenNodeKind.has:
        final target = node.positionalArgs.isEmpty
            ? ''
            : ' ${node.positionalArgs.first}';
        lines.add('${_pad(depth)}has$target');
      case RenPyScreenNodeKind.keyword:
        final keyword = node.keyword ?? node.kind;
        final header =
            node.value == null ? keyword : '$keyword ${node.value}';
        if (node.children.isEmpty) {
          lines.add('${_pad(depth)}$header');
        } else {
          lines.add('${_pad(depth)}$header:');
          for (final child in node.children) {
            _screenNode(child, depth + 1, lines);
          }
        }
    }
  }

  void _screenDisplayable(
    RenPyScreenNode node,
    int depth,
    List<String> lines,
  ) {
    if (node.children.isEmpty) {
      // Single-line form: `kind pos... prop value... flag...`. Value-less
      // properties trail so they cannot swallow a following property name.
      final tokens = <String>[node.kind, ...node.positionalArgs];
      final flags = <String>[];
      node.properties.forEach((key, value) {
        if (value.isEmpty) {
          flags.add(key);
        } else {
          tokens.add('$key $value');
        }
      });
      tokens.addAll(flags);
      lines.add('${_pad(depth)}${tokens.join(' ')}');
      return;
    }

    // Block form: positional args stay on the header; properties become
    // indented body lines unless their key would be misread as a child
    // statement, in which case they stay inline on the header.
    final headerTokens = <String>[node.kind, ...node.positionalArgs];
    final bodyProperties = <MapEntry<String, String>>[];
    node.properties.forEach((key, value) {
      if (_blockSafeProperty(key, value)) {
        bodyProperties.add(MapEntry(key, value));
      } else {
        headerTokens.add(value.isEmpty ? key : '$key $value');
      }
    });
    lines.add('${_pad(depth)}${headerTokens.join(' ')}:');
    for (final entry in bodyProperties) {
      final text = entry.value.isEmpty
          ? entry.key
          : '${entry.key} ${entry.value}';
      lines.add('${_pad(depth + 1)}$text');
    }
    for (final child in node.children) {
      _screenNode(child, depth + 1, lines);
    }
  }

  /// Whether a screen property may be emitted as a standalone `key value`
  /// body line without being misparsed as a child node.
  bool _blockSafeProperty(String key, String value) {
    if (!_identifierPattern.hasMatch(key)) return false;
    if (_displayableKeywords.contains(key)) return false;
    if (renPyScreenKeywords.contains(key)) return false;
    if (_screenControlWords.contains(key)) return false;
    if (value.endsWith(':') || value.contains('\n')) return false;
    return true;
  }

  // --------------------------------------------------------------------
  // Layered images
  // --------------------------------------------------------------------

  void _layeredImage(
    RenPyLayeredImageStatement statement,
    int depth,
    List<String> lines,
  ) {
    lines.add('${_pad(depth)}layeredimage ${statement.name}:');
    final layers = statement.layers;
    var i = 0;
    while (i < layers.length) {
      final layer = layers[i];
      switch (layer.kind) {
        case RenPyLayeredImageLayerKind.always:
          lines.add('${_pad(depth + 1)}always:');
          _layerBody(layer, depth + 2, lines);
          i += 1;
        case RenPyLayeredImageLayerKind.condition:
          lines.add('${_pad(depth + 1)}if ${layer.condition}:');
          _layerBody(layer, depth + 2, lines);
          i += 1;
        case RenPyLayeredImageLayerKind.attribute:
          if (layer.group == layer.attribute) {
            // An attribute whose group matches its own name re-parses
            // identically from the bare `attribute name:` form.
            lines.add(
              '${_pad(depth + 1)}attribute ${layer.attribute}'
              '${layer.isDefault ? ' default' : ''}:',
            );
            _layerBody(layer, depth + 2, lines);
            i += 1;
          } else {
            lines.add('${_pad(depth + 1)}group ${layer.group}:');
            while (i < layers.length &&
                layers[i].kind == RenPyLayeredImageLayerKind.attribute &&
                layers[i].group == layer.group) {
              final member = layers[i];
              lines.add(
                '${_pad(depth + 2)}attribute ${member.attribute}'
                '${member.isDefault ? ' default' : ''}:',
              );
              _layerBody(member, depth + 3, lines);
              i += 1;
            }
          }
      }
    }
  }

  void _layerBody(
    RenPyLayeredImageLayer layer,
    int depth,
    List<String> lines,
  ) {
    lines.add('${_pad(depth)}"${layer.displayable}"');
    layer.properties.forEach((key, value) {
      lines.add('${_pad(depth)}$key $value');
    });
  }

  // --------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------

  String _pad(int depth) => indent * depth;

  /// Emits a nested statement block, substituting an explicit `pass` line for
  /// an empty block so the emitted text re-parses.
  void _block(List<RenPyStatement> block, int depth, List<String> lines) {
    if (block.isEmpty) {
      lines.add('${_pad(depth)}pass');
      return;
    }
    for (final statement in block) {
      _statement(statement, depth, lines);
    }
  }

  /// Emits raw (already relatively indented) source lines, e.g. a python
  /// block body, prefixing each non-blank line with the block indentation.
  void _rawLines(String code, int depth, List<String> lines) {
    for (final line in code.split('\n')) {
      lines.add(line.trim().isEmpty ? '' : '${_pad(depth)}$line');
    }
  }

  /// Wraps [value] in double quotes, escaping exactly the sequences the
  /// parser's string unescaper understands (`\\`, `\"`, `\n`, `\t`).
  String _quote(String value) {
    final buffer = StringBuffer('"');
    for (var i = 0; i < value.length; i += 1) {
      final character = value[i];
      switch (character) {
        case '\\':
          buffer.write(r'\\');
        case '"':
          buffer.write(r'\"');
        case '\n':
          buffer.write(r'\n');
        case '\t':
          buffer.write(r'\t');
        default:
          buffer.write(character);
      }
    }
    buffer.write('"');
    return buffer.toString();
  }
}
