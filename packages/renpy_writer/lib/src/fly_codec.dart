import 'dart:convert';

import 'package:renpy_parser/renpy_parser.dart';

/// Thrown when a .fly document is structurally invalid: wrong envelope,
/// unknown statement type, unknown key, missing required field, or a field
/// with the wrong JSON type.
class FlyFormatException implements Exception {
  FlyFormatException(this.message, {this.path});

  /// Human-readable description of what is wrong.
  final String message;

  /// JSON-pointer-ish location of the offending value, e.g.
  /// `/script/3/items/0/text`. Null when the error is not tied to a
  /// particular location (e.g. unparseable JSON).
  final String? path;

  @override
  String toString() => path == null
      ? 'FlyFormatException: $message'
      : 'FlyFormatException at $path: $message';
}

/// Codec between the renpy_parser AST ([RenPyScript]) and the strictly-typed
/// JSON-based .fly interchange format (see `doc/fly_format.md`).
///
/// Encoding is lossless for every semantic AST field. Source positions
/// (`filename` / `linenumber`) are *not* preserved: decoding synthesizes a
/// fresh filename (the `filename` argument) and sequential line numbers.
class FlyCodec {
  const FlyCodec();

  /// The value of the document `"format"` key.
  static const String formatName = 'fly';

  /// The current document `"version"`.
  static const int formatVersion = 1;

  // ---------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------

  /// Encodes [script] into a .fly document map (envelope included).
  Map<String, Object?> encodeScript(RenPyScript script) {
    return <String, Object?>{
      'format': formatName,
      'version': formatVersion,
      'script': [for (final s in script.statements) _encodeStatement(s)],
    };
  }

  /// Encodes [script] to .fly JSON text. When [pretty] is true (the default)
  /// the output is indented with two spaces.
  String encodeToString(RenPyScript script, {bool pretty = true}) {
    final document = encodeScript(script);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(document)
        : jsonEncode(document);
  }

  Map<String, Object?> _encodeStatement(RenPyStatement s) {
    if (s is RenPyLabelStatement) {
      return _obj('label', {
        'name': s.name,
        'parameters': [for (final p in s.parameters) _encodeParameter(p)],
        'block': _encodeBlock(s.block),
      });
    }
    if (s is RenPySayStatement) {
      return _obj('say', {
        'character': s.character,
        'text': s.text,
        'attributes': s.attributes,
        'temporary_attributes': s.temporaryAttributes,
      });
    }
    if (s is RenPyMenuStatement) {
      return _obj('menu', {
        'items': [
          for (final choice in s.items)
            _clean({
              'text': choice.text,
              'condition': choice.condition,
              'block': _encodeBlock(choice.block),
            }),
        ],
        'caption': s.caption,
        'set_variable': s.setVariable,
        'name': s.name,
      });
    }
    if (s is RenPyJumpStatement) {
      return _obj('jump', {
        'target': s.target,
        'is_expression': s.isExpression,
      });
    }
    if (s is RenPyCallStatement) {
      return _obj('call', {
        'target': s.target,
        'is_expression': s.isExpression,
        'is_screen': s.isScreen,
        'screen_name': s.screenName,
        'screen_args': s.screenArgs,
        'call_args': s.callArgs,
      });
    }
    if (s is RenPyShowStatement) {
      return _obj('show', {
        'image_name': s.imageName,
        'at_expression': s.atExpression,
        'behind_expression': s.behindExpression,
        'on_layer_expression': s.onLayerExpression,
        'z_order_expression': s.zOrderExpression,
        'with_expression': s.withExpression,
        'displayable_text': s.displayableText,
      });
    }
    if (s is RenPySceneStatement) {
      return _obj('scene', {
        'image_name': s.imageName,
        'at_expression': s.atExpression,
        'on_layer_expression': s.onLayerExpression,
        'z_order_expression': s.zOrderExpression,
        'with_expression': s.withExpression,
      });
    }
    if (s is RenPyHideStatement) {
      return _obj('hide', {
        'image_name': s.imageName,
        'on_layer_expression': s.onLayerExpression,
        'with_expression': s.withExpression,
      });
    }
    if (s is RenPyImageStatement) {
      return _obj('image', {
        'name': s.name,
        'expression': s.expression.isEmpty ? null : s.expression,
        'body': s.body,
      });
    }
    if (s is RenPyLayeredImageStatement) {
      return _obj('layeredimage', {
        'name': s.name,
        'layers': [for (final layer in s.layers) _encodeLayer(layer)],
      });
    }
    if (s is RenPyCameraStatement) {
      return _obj('camera', {
        'layer': s.layer,
        'at_expression': s.atExpression,
        'with_expression': s.withExpression,
        'body': s.body,
      });
    }
    if (s is RenPyTranslateStatement) {
      return _obj('translate', {
        'language': s.language,
        'label': s.label,
        'block': _encodeBlock(s.block),
        'strings': s.strings,
      });
    }
    if (s is RenPyWithStatement) {
      return _obj('with', {'transition': s.transition});
    }
    if (s is RenPyTransformStatement) {
      return _obj('transform', {
        'signature': s.signature,
        'body': s.body,
        'atl': [for (final node in s.atl) _encodeAtlNode(node)],
      });
    }
    if (s is RenPyPlayStatement) {
      return _obj('play', {'channel': s.channel, 'expression': s.expression});
    }
    if (s is RenPyQueueStatement) {
      return _obj('queue', {'channel': s.channel, 'expression': s.expression});
    }
    if (s is RenPyVoiceStatement) {
      return _obj('voice', {'expression': s.expression});
    }
    if (s is RenPyStopStatement) {
      return _obj('stop', {'channel': s.channel, 'fadeout': s.fadeout});
    }
    if (s is RenPyPauseStatement) {
      return _obj('pause', {'duration': s.duration});
    }
    if (s is RenPyWindowStatement) {
      return _obj('window', {
        'action': s.action.name,
        'transition': s.transition,
      });
    }
    if (s is RenPyPythonStatement) {
      return _obj('python', {'code': s.code, 'is_init': s.isInit});
    }
    if (s is RenPyInitStatement) {
      return _obj('init', {
        'priority': s.priority,
        'is_python': s.isPython,
        'block': _encodeBlock(s.block),
      });
    }
    if (s is RenPyInitOffsetStatement) {
      return _obj('init_offset', {'offset': s.offset});
    }
    if (s is RenPyDefineStatement) {
      return _obj('define', {'name': s.name, 'expression': s.expression});
    }
    if (s is RenPyDefaultStatement) {
      return _obj('default', {'name': s.name, 'expression': s.expression});
    }
    if (s is RenPyScreenStatement) {
      return _obj('screen', {
        'signature': s.signature,
        'children': [for (final node in s.children) _encodeScreenNode(node)],
      });
    }
    if (s is RenPyStyleStatement) {
      return _obj('style', {
        'declaration': s.declaration,
        'style': s.style == null ? null : _encodeStyle(s.style!),
      });
    }
    if (s is RenPyNvlStatement) {
      return _obj('nvl', {'action': s.action.name});
    }
    if (s is RenPyIfStatement) {
      return _obj('if', {
        'branches': [
          for (final entry in s.entries)
            _clean({
              'condition': entry.condition,
              'block': _encodeBlock(entry.block),
            }),
        ],
      });
    }
    if (s is RenPyWhileStatement) {
      return _obj('while', {
        'condition': s.condition,
        'block': _encodeBlock(s.block),
      });
    }
    if (s is RenPyForStatement) {
      return _obj('for', {
        'variable': s.variable,
        'iterable': s.iterable,
        'block': _encodeBlock(s.block),
      });
    }
    if (s is RenPyLoopControlStatement) {
      return _obj(
        s.action == RenPyLoopControlAction.breakLoop ? 'break' : 'continue',
        const {},
      );
    }
    if (s is RenPyPassStatement) {
      return _obj('pass', const {});
    }
    if (s is RenPyReturnStatement) {
      return _obj('return', {'expression': s.expression});
    }
    if (s is RenPyGenericStatement) {
      return _obj('raw', {'text': s.text});
    }
    throw ArgumentError(
      'Unsupported statement type for .fly encoding: ${s.runtimeType}',
    );
  }

  List<Map<String, Object?>> _encodeBlock(List<RenPyStatement> block) {
    return [for (final s in block) _encodeStatement(s)];
  }

  Map<String, Object?> _encodeParameter(RenPyParameter p) {
    return _clean({
      'name': p.name,
      'default_expression': p.defaultExpression,
    });
  }

  Map<String, Object?> _encodeLayer(RenPyLayeredImageLayer layer) {
    return _clean({
      'kind': layer.kind.name,
      'displayable': layer.displayable,
      'group': layer.group,
      'attribute': layer.attribute,
      'is_default': layer.isDefault,
      'condition': layer.condition,
      'properties': layer.properties,
    });
  }

  Map<String, Object?> _encodeScreenNode(RenPyScreenNode node) {
    return _clean({
      'kind': node.kind,
      'node_kind': _screenNodeKindToJson[node.nodeKind],
      'positional_args': node.positionalArgs,
      'properties': node.properties,
      'children': [for (final c in node.children) _encodeScreenNode(c)],
      'branches': [
        for (final branch in node.branches)
          _clean({
            'condition': branch.condition,
            'children': [
              for (final c in branch.children) _encodeScreenNode(c),
            ],
          }),
      ],
      'for_target': node.forTarget,
      'for_iterable': node.forIterable,
      'python_code': node.pythonCode,
      'event': node.event,
      'keyword': node.keyword,
      'value': node.value,
    });
  }

  Map<String, Object?> _encodeStyle(RenPyStyle style) {
    return _clean({
      'name': style.name,
      'parent': style.parent,
      'properties': style.properties,
    });
  }

  Map<String, Object?> _encodeAtlNode(RenPyAtlNode node) {
    return _clean({
      'node_kind': node.nodeKind.name,
      'properties': node.properties,
      'warper': node.warper,
      'duration': node.duration,
      'repeat_count': node.repeatCount,
      'event': node.event,
      'contains_expression': node.containsExpression,
      'children': [for (final c in node.children) _encodeAtlNode(c)],
      'raw': node.raw,
    });
  }

  /// Builds a statement object: `type` discriminator first, then [fields]
  /// with default-valued entries dropped (see [_clean]).
  Map<String, Object?> _obj(String type, Map<String, Object?> fields) {
    return <String, Object?>{'type': type, ..._clean(fields)};
  }

  /// Drops entries whose value is its documented default: null, `false`, an
  /// empty list, or an empty map. The decoder restores the defaults.
  Map<String, Object?> _clean(Map<String, Object?> fields) {
    final out = <String, Object?>{};
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is bool && !value) continue;
      if (value is List && value.isEmpty) continue;
      if (value is Map && value.isEmpty) continue;
      out[entry.key] = value;
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Decoding
  // ---------------------------------------------------------------------

  /// Decodes .fly JSON text into a [RenPyScript].
  ///
  /// Throws [FlyFormatException] on invalid JSON or an invalid document.
  RenPyScript decodeFromString(String source, {String filename = '<fly>'}) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FlyFormatException('document is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw FlyFormatException(
        'document must be a JSON object, got ${_jsonTypeName(decoded)}',
        path: '',
      );
    }
    return decodeScript(decoded, filename: filename);
  }

  /// Decodes a .fly document map (envelope included) into a [RenPyScript].
  ///
  /// Source positions are synthesized: every statement gets [filename] and a
  /// sequential line number in document order.
  ///
  /// Throws [FlyFormatException] on any structural problem.
  RenPyScript decodeScript(
    Map<String, Object?> document, {
    String filename = '<fly>',
  }) {
    for (final key in document.keys) {
      if (key != 'format' && key != 'version' && key != 'script') {
        throw FlyFormatException(
          'unknown document key "$key"',
          path: '/$key',
        );
      }
    }

    if (!document.containsKey('format')) {
      throw FlyFormatException('missing required key "format"', path: '');
    }
    final format = document['format'];
    if (format is! String) {
      throw FlyFormatException(
        '"format" must be a string, got ${_jsonTypeName(format)}',
        path: '/format',
      );
    }
    if (format != formatName) {
      throw FlyFormatException(
        '"format" must be "$formatName", got "$format"',
        path: '/format',
      );
    }

    if (!document.containsKey('version')) {
      throw FlyFormatException('missing required key "version"', path: '');
    }
    final version = document['version'];
    if (version is! int) {
      throw FlyFormatException(
        '"version" must be an integer, got ${_jsonTypeName(version)}',
        path: '/version',
      );
    }
    if (version != formatVersion) {
      throw FlyFormatException(
        'unsupported version $version (this codec reads version '
        '$formatVersion)',
        path: '/version',
      );
    }

    if (!document.containsKey('script')) {
      throw FlyFormatException('missing required key "script"', path: '');
    }
    final script = document['script'];
    if (script is! List<Object?>) {
      throw FlyFormatException(
        '"script" must be a list, got ${_jsonTypeName(script)}',
        path: '/script',
      );
    }

    final ctx = _DecodeContext(filename);
    final statements = <RenPyStatement>[
      for (var i = 0; i < script.length; i++)
        _decodeStatement(ctx, script[i], '/script/$i'),
    ];
    return RenPyScript(statements);
  }

  RenPyStatement _decodeStatement(
    _DecodeContext ctx,
    Object? value,
    String path,
  ) {
    final o = _Obj.of(value, path, what: 'statement');
    final type = o.requiredString('type');
    final filename = ctx.filename;
    final line = ctx.nextLine();

    switch (type) {
      case 'label':
        o.allow(const {'type', 'name', 'parameters', 'block'});
        final name = o.requiredString('name');
        final parameters = _decodeParameters(o, 'parameters');
        return RenPyLabelStatement(
          name,
          _decodeBlock(ctx, o, 'block'),
          filename,
          line,
          parameters: parameters,
        );

      case 'say':
        o.allow(const {
          'type',
          'character',
          'text',
          'attributes',
          'temporary_attributes',
        });
        return RenPySayStatement(
          o.optionalString('character'),
          o.optionalString('text'),
          filename,
          line,
          attributes: o.stringList('attributes'),
          temporaryAttributes: o.stringList('temporary_attributes'),
        );

      case 'menu':
        o.allow(const {
          'type',
          'items',
          'caption',
          'set_variable',
          'name',
        });
        final rawItems = o.optionalList('items');
        final items = <MenuChoice>[
          for (var i = 0; i < rawItems.length; i++)
            _decodeMenuChoice(ctx, rawItems[i], '$path/items/$i'),
        ];
        return RenPyMenuStatement(
          items,
          filename,
          line,
          caption: o.optionalString('caption'),
          setVariable: o.optionalString('set_variable'),
          name: o.optionalString('name'),
        );

      case 'jump':
        o.allow(const {'type', 'target', 'is_expression'});
        return RenPyJumpStatement(
          o.requiredString('target'),
          filename,
          line,
          isExpression: o.optionalBool('is_expression'),
        );

      case 'call':
        o.allow(const {
          'type',
          'target',
          'is_expression',
          'is_screen',
          'screen_name',
          'screen_args',
          'call_args',
        });
        return RenPyCallStatement(
          o.requiredString('target'),
          filename,
          line,
          isExpression: o.optionalBool('is_expression'),
          isScreen: o.optionalBool('is_screen'),
          screenName: o.optionalString('screen_name'),
          screenArgs: o.optionalString('screen_args'),
          callArgs: o.optionalString('call_args'),
        );

      case 'show':
        o.allow(const {
          'type',
          'image_name',
          'at_expression',
          'behind_expression',
          'on_layer_expression',
          'z_order_expression',
          'with_expression',
          'displayable_text',
        });
        return RenPyShowStatement(
          o.requiredString('image_name'),
          o.optionalString('at_expression'),
          o.optionalString('with_expression'),
          filename,
          line,
          behindExpression: o.optionalString('behind_expression'),
          onLayerExpression: o.optionalString('on_layer_expression'),
          zOrderExpression: o.optionalString('z_order_expression'),
          displayableText: o.optionalString('displayable_text'),
        );

      case 'scene':
        o.allow(const {
          'type',
          'image_name',
          'at_expression',
          'on_layer_expression',
          'z_order_expression',
          'with_expression',
        });
        return RenPySceneStatement(
          o.optionalString('image_name'),
          o.optionalString('at_expression'),
          o.optionalString('with_expression'),
          filename,
          line,
          onLayerExpression: o.optionalString('on_layer_expression'),
          zOrderExpression: o.optionalString('z_order_expression'),
        );

      case 'hide':
        o.allow(const {
          'type',
          'image_name',
          'on_layer_expression',
          'with_expression',
        });
        return RenPyHideStatement(
          o.requiredString('image_name'),
          o.optionalString('with_expression'),
          filename,
          line,
          onLayerExpression: o.optionalString('on_layer_expression'),
        );

      case 'image':
        o.allow(const {'type', 'name', 'expression', 'body'});
        return RenPyImageStatement(
          o.requiredString('name'),
          o.optionalString('expression') ?? '',
          filename,
          line,
          body: o.stringList('body'),
        );

      case 'layeredimage':
        o.allow(const {'type', 'name', 'layers'});
        final rawLayers = o.optionalList('layers');
        final layers = <RenPyLayeredImageLayer>[
          for (var i = 0; i < rawLayers.length; i++)
            _decodeLayer(rawLayers[i], '$path/layers/$i'),
        ];
        return RenPyLayeredImageStatement(
          o.requiredString('name'),
          layers,
          filename,
          line,
        );

      case 'camera':
        o.allow(const {
          'type',
          'layer',
          'at_expression',
          'with_expression',
          'body',
        });
        return RenPyCameraStatement(
          o.optionalString('layer'),
          o.optionalString('at_expression'),
          o.optionalString('with_expression'),
          filename,
          line,
          body: o.stringList('body'),
        );

      case 'translate':
        o.allow(const {'type', 'language', 'label', 'block', 'strings'});
        return RenPyTranslateStatement(
          o.requiredString('language'),
          o.requiredString('label'),
          _decodeBlock(ctx, o, 'block'),
          filename,
          line,
          strings: o.stringList('strings'),
        );

      case 'with':
        o.allow(const {'type', 'transition'});
        return RenPyWithStatement(
          o.requiredString('transition'),
          filename,
          line,
        );

      case 'transform':
        o.allow(const {'type', 'signature', 'body', 'atl'});
        final rawAtl = o.optionalList('atl');
        return RenPyTransformStatement(
          o.requiredString('signature'),
          filename,
          line,
          body: o.stringList('body'),
          atl: [
            for (var i = 0; i < rawAtl.length; i++)
              _decodeAtlNode(rawAtl[i], '$path/atl/$i'),
          ],
        );

      case 'play':
        o.allow(const {'type', 'channel', 'expression'});
        return RenPyPlayStatement(
          o.requiredString('channel'),
          o.requiredString('expression'),
          filename,
          line,
        );

      case 'queue':
        o.allow(const {'type', 'channel', 'expression'});
        return RenPyQueueStatement(
          o.requiredString('channel'),
          o.requiredString('expression'),
          filename,
          line,
        );

      case 'voice':
        o.allow(const {'type', 'expression'});
        return RenPyVoiceStatement(
          o.requiredString('expression'),
          filename,
          line,
        );

      case 'stop':
        o.allow(const {'type', 'channel', 'fadeout'});
        return RenPyStopStatement(
          o.requiredString('channel'),
          o.optionalString('fadeout'),
          filename,
          line,
        );

      case 'pause':
        o.allow(const {'type', 'duration'});
        return RenPyPauseStatement(
          o.optionalString('duration'),
          filename,
          line,
        );

      case 'window':
        o.allow(const {'type', 'action', 'transition'});
        final action = o.requiredString('action');
        return RenPyWindowStatement(
          _windowActionFromJson(action, '$path/action'),
          filename,
          line,
          transition: o.optionalString('transition'),
        );

      case 'python':
        o.allow(const {'type', 'code', 'is_init'});
        return RenPyPythonStatement(
          o.requiredString('code'),
          o.optionalBool('is_init'),
          filename,
          line,
        );

      case 'init':
        o.allow(const {'type', 'priority', 'is_python', 'block'});
        return RenPyInitStatement(
          priority: o.optionalInt('priority'),
          isPython: o.optionalBool('is_python'),
          block: _decodeBlock(ctx, o, 'block'),
          filename: filename,
          linenumber: line,
        );

      case 'init_offset':
        o.allow(const {'type', 'offset'});
        return RenPyInitOffsetStatement(
          o.requiredInt('offset'),
          filename,
          line,
        );

      case 'define':
        o.allow(const {'type', 'name', 'expression'});
        return RenPyDefineStatement(
          o.requiredString('name'),
          o.requiredString('expression'),
          filename,
          line,
        );

      case 'default':
        o.allow(const {'type', 'name', 'expression'});
        return RenPyDefaultStatement(
          o.requiredString('name'),
          o.requiredString('expression'),
          filename,
          line,
        );

      case 'screen':
        o.allow(const {'type', 'signature', 'children'});
        return RenPyScreenStatement(
          o.requiredString('signature'),
          filename,
          line,
          children: _decodeScreenNodes(o, 'children'),
        );

      case 'style':
        o.allow(const {'type', 'declaration', 'style'});
        final rawStyle = o.optionalObject('style');
        return RenPyStyleStatement(
          o.requiredString('declaration'),
          filename,
          line,
          style: rawStyle == null
              ? null
              : _decodeStyle(rawStyle, '$path/style'),
        );

      case 'nvl':
        o.allow(const {'type', 'action'});
        final action = o.requiredString('action');
        if (action != 'clear') {
          throw FlyFormatException(
            'unknown nvl action "$action" (expected "clear")',
            path: '$path/action',
          );
        }
        return RenPyNvlStatement(RenPyNvlAction.clear, filename, line);

      case 'if':
        o.allow(const {'type', 'branches'});
        final rawBranches = o.requiredList('branches');
        final entries = <IfEntry>[
          for (var i = 0; i < rawBranches.length; i++)
            _decodeIfEntry(ctx, rawBranches[i], '$path/branches/$i'),
        ];
        return RenPyIfStatement(entries, filename, line);

      case 'while':
        o.allow(const {'type', 'condition', 'block'});
        return RenPyWhileStatement(
          o.requiredString('condition'),
          _decodeBlock(ctx, o, 'block'),
          filename,
          line,
        );

      case 'for':
        o.allow(const {'type', 'variable', 'iterable', 'block'});
        return RenPyForStatement(
          o.requiredString('variable'),
          o.requiredString('iterable'),
          _decodeBlock(ctx, o, 'block'),
          filename,
          line,
        );

      case 'break':
        o.allow(const {'type'});
        return RenPyLoopControlStatement(
          RenPyLoopControlAction.breakLoop,
          filename,
          line,
        );

      case 'continue':
        o.allow(const {'type'});
        return RenPyLoopControlStatement(
          RenPyLoopControlAction.continueLoop,
          filename,
          line,
        );

      case 'pass':
        o.allow(const {'type'});
        return RenPyPassStatement(filename, line);

      case 'return':
        o.allow(const {'type', 'expression'});
        return RenPyReturnStatement(
          o.optionalString('expression'),
          filename,
          line,
        );

      case 'raw':
        o.allow(const {'type', 'text'});
        return RenPyGenericStatement(o.requiredString('text'), filename, line);

      default:
        throw FlyFormatException(
          'unknown statement type "$type"',
          path: '$path/type',
        );
    }
  }

  List<RenPyStatement> _decodeBlock(_DecodeContext ctx, _Obj o, String key) {
    final raw = o.optionalList(key);
    return [
      for (var i = 0; i < raw.length; i++)
        _decodeStatement(ctx, raw[i], '${o.path}/$key/$i'),
    ];
  }

  List<RenPyParameter> _decodeParameters(_Obj o, String key) {
    final raw = o.optionalList(key);
    return [
      for (var i = 0; i < raw.length; i++)
        _decodeParameter(raw[i], '${o.path}/$key/$i'),
    ];
  }

  RenPyParameter _decodeParameter(Object? value, String path) {
    final p = _Obj.of(value, path, what: 'parameter');
    p.allow(const {'name', 'default_expression'});
    return RenPyParameter(
      p.requiredString('name'),
      p.optionalString('default_expression'),
    );
  }

  MenuChoice _decodeMenuChoice(_DecodeContext ctx, Object? value, String path) {
    final c = _Obj.of(value, path, what: 'menu choice');
    c.allow(const {'text', 'condition', 'block'});
    return MenuChoice(
      text: c.requiredString('text'),
      condition: c.optionalString('condition') ?? 'True',
      block: _decodeBlock(ctx, c, 'block'),
    );
  }

  IfEntry _decodeIfEntry(_DecodeContext ctx, Object? value, String path) {
    final e = _Obj.of(value, path, what: 'if branch');
    e.allow(const {'condition', 'block'});
    return IfEntry(
      e.requiredString('condition'),
      _decodeBlock(ctx, e, 'block'),
    );
  }

  RenPyLayeredImageLayer _decodeLayer(Object? value, String path) {
    final l = _Obj.of(value, path, what: 'layeredimage layer');
    l.allow(const {
      'kind',
      'displayable',
      'group',
      'attribute',
      'is_default',
      'condition',
      'properties',
    });
    final kindName = l.requiredString('kind');
    final kind = _layerKindFromJson[kindName];
    if (kind == null) {
      throw FlyFormatException(
        'unknown layer kind "$kindName" (expected one of: '
        '${_layerKindFromJson.keys.join(', ')})',
        path: '$path/kind',
      );
    }
    return RenPyLayeredImageLayer(
      kind: kind,
      displayable: l.requiredString('displayable'),
      group: l.optionalString('group'),
      attribute: l.optionalString('attribute'),
      isDefault: l.optionalBool('is_default'),
      condition: l.optionalString('condition'),
      properties: l.stringMap('properties'),
    );
  }

  List<RenPyScreenNode> _decodeScreenNodes(_Obj o, String key) {
    final raw = o.optionalList(key);
    return [
      for (var i = 0; i < raw.length; i++)
        _decodeScreenNode(raw[i], '${o.path}/$key/$i'),
    ];
  }

  RenPyScreenNode _decodeScreenNode(Object? value, String path) {
    final n = _Obj.of(value, path, what: 'screen node');
    n.allow(const {
      'kind',
      'node_kind',
      'positional_args',
      'properties',
      'children',
      'branches',
      'for_target',
      'for_iterable',
      'python_code',
      'event',
      'keyword',
      'value',
    });
    final kindName = n.requiredString('node_kind');
    final nodeKind = _screenNodeKindFromJson[kindName];
    if (nodeKind == null) {
      throw FlyFormatException(
        'unknown screen node kind "$kindName" (expected one of: '
        '${_screenNodeKindFromJson.keys.join(', ')})',
        path: '$path/node_kind',
      );
    }
    final rawBranches = n.optionalList('branches');
    return RenPyScreenNode(
      kind: n.requiredString('kind'),
      nodeKind: nodeKind,
      positionalArgs: n.stringList('positional_args'),
      properties: n.stringMap('properties'),
      children: _decodeScreenNodes(n, 'children'),
      branches: [
        for (var i = 0; i < rawBranches.length; i++)
          _decodeScreenBranch(rawBranches[i], '$path/branches/$i'),
      ],
      forTarget: n.optionalString('for_target'),
      forIterable: n.optionalString('for_iterable'),
      pythonCode: n.optionalString('python_code'),
      event: n.optionalString('event'),
      keyword: n.optionalString('keyword'),
      value: n.optionalString('value'),
    );
  }

  RenPyScreenConditionalBranch _decodeScreenBranch(Object? value, String path) {
    final b = _Obj.of(value, path, what: 'screen branch');
    b.allow(const {'condition', 'children'});
    return RenPyScreenConditionalBranch(
      b.requiredString('condition'),
      _decodeScreenNodes(b, 'children'),
    );
  }

  RenPyStyle _decodeStyle(Map<String, Object?> value, String path) {
    final s = _Obj(value, path);
    s.allow(const {'name', 'parent', 'properties'});
    return RenPyStyle(
      name: s.requiredString('name'),
      parent: s.optionalString('parent'),
      properties: s.stringMap('properties'),
    );
  }

  RenPyAtlNode _decodeAtlNode(Object? value, String path) {
    final n = _Obj.of(value, path, what: 'ATL node');
    n.allow(const {
      'node_kind',
      'properties',
      'warper',
      'duration',
      'repeat_count',
      'event',
      'contains_expression',
      'children',
      'raw',
    });
    final kindName = n.requiredString('node_kind');
    final nodeKind = _atlNodeKindFromJson[kindName];
    if (nodeKind == null) {
      throw FlyFormatException(
        'unknown ATL node kind "$kindName" (expected one of: '
        '${_atlNodeKindFromJson.keys.join(', ')})',
        path: '$path/node_kind',
      );
    }
    final rawChildren = n.optionalList('children');
    return RenPyAtlNode(
      nodeKind: nodeKind,
      properties: n.stringMap('properties'),
      warper: n.optionalString('warper'),
      duration: n.optionalString('duration'),
      repeatCount: n.optionalString('repeat_count'),
      event: n.optionalString('event'),
      containsExpression: n.optionalString('contains_expression'),
      children: [
        for (var i = 0; i < rawChildren.length; i++)
          _decodeAtlNode(rawChildren[i], '$path/children/$i'),
      ],
      raw: n.optionalString('raw'),
    );
  }

  RenPyWindowAction _windowActionFromJson(String name, String path) {
    return switch (name) {
      'show' => RenPyWindowAction.show,
      'hide' => RenPyWindowAction.hide,
      'auto' => RenPyWindowAction.auto,
      _ => throw FlyFormatException(
          'unknown window action "$name" (expected show, hide, or auto)',
          path: path,
        ),
    };
  }
}

const Map<RenPyScreenNodeKind, String> _screenNodeKindToJson = {
  RenPyScreenNodeKind.displayable: 'displayable',
  RenPyScreenNodeKind.ifChain: 'if_chain',
  RenPyScreenNodeKind.forLoop: 'for_loop',
  RenPyScreenNodeKind.python: 'python',
  RenPyScreenNodeKind.pythonBlock: 'python_block',
  RenPyScreenNodeKind.on: 'on',
  RenPyScreenNodeKind.use: 'use',
  RenPyScreenNodeKind.transclude: 'transclude',
  RenPyScreenNodeKind.has: 'has',
  RenPyScreenNodeKind.keyword: 'keyword',
};

final Map<String, RenPyScreenNodeKind> _screenNodeKindFromJson = {
  for (final entry in _screenNodeKindToJson.entries) entry.value: entry.key,
};

const Map<String, RenPyAtlNodeKind> _atlNodeKindFromJson = {
  'property': RenPyAtlNodeKind.property,
  'interpolation': RenPyAtlNodeKind.interpolation,
  'pause': RenPyAtlNodeKind.pause,
  'repeat': RenPyAtlNodeKind.repeat,
  'block': RenPyAtlNodeKind.block,
  'parallel': RenPyAtlNodeKind.parallel,
  'choice': RenPyAtlNodeKind.choice,
  'on': RenPyAtlNodeKind.on,
  'contains': RenPyAtlNodeKind.contains,
  'raw': RenPyAtlNodeKind.raw,
};

const Map<String, RenPyLayeredImageLayerKind> _layerKindFromJson = {
  'always': RenPyLayeredImageLayerKind.always,
  'attribute': RenPyLayeredImageLayerKind.attribute,
  'condition': RenPyLayeredImageLayerKind.condition,
};

/// Per-decode mutable state: the synthetic filename and a running line
/// counter so each decoded statement gets a unique, ordered line number.
class _DecodeContext {
  _DecodeContext(this.filename);

  final String filename;
  int _line = 0;

  int nextLine() => ++_line;
}

/// A strictly-validated view over a JSON object, tracking its document
/// [path] for error reporting.
class _Obj {
  _Obj(this.map, this.path);

  /// Casts [value] to a JSON object or throws with a useful [path].
  factory _Obj.of(Object? value, String path, {required String what}) {
    if (value is! Map<String, Object?>) {
      throw FlyFormatException(
        '$what must be a JSON object, got ${_jsonTypeName(value)}',
        path: path,
      );
    }
    return _Obj(value, path);
  }

  final Map<String, Object?> map;
  final String path;

  /// Rejects any key not in [allowed].
  void allow(Set<String> allowed) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw FlyFormatException('unknown key "$key"', path: '$path/$key');
      }
    }
  }

  T _required<T>(String key, String typeName) {
    if (!map.containsKey(key)) {
      throw FlyFormatException('missing required key "$key"', path: path);
    }
    final value = map[key];
    if (value is! T) {
      throw FlyFormatException(
        '"$key" must be $typeName, got ${_jsonTypeName(value)}',
        path: '$path/$key',
      );
    }
    return value;
  }

  T? _optional<T>(String key, String typeName) {
    final value = map[key];
    if (value == null) return null;
    if (value is T) return value as T;
    throw FlyFormatException(
      '"$key" must be $typeName, got ${_jsonTypeName(value)}',
      path: '$path/$key',
    );
  }

  String requiredString(String key) => _required<String>(key, 'a string');

  String? optionalString(String key) => _optional<String>(key, 'a string');

  int requiredInt(String key) => _required<int>(key, 'an integer');

  int optionalInt(String key, {int defaultValue = 0}) =>
      _optional<int>(key, 'an integer') ?? defaultValue;

  bool optionalBool(String key) => _optional<bool>(key, 'a boolean') ?? false;

  List<Object?> requiredList(String key) =>
      _required<List<Object?>>(key, 'a list');

  List<Object?> optionalList(String key) =>
      _optional<List<Object?>>(key, 'a list') ?? const [];

  Map<String, Object?>? optionalObject(String key) =>
      _optional<Map<String, Object?>>(key, 'an object');

  /// An optional list whose entries must all be strings.
  List<String> stringList(String key) {
    final raw = optionalList(key);
    return [
      for (var i = 0; i < raw.length; i++)
        raw[i] is String
            ? raw[i] as String
            : (throw FlyFormatException(
                '"$key" entries must be strings, got '
                '${_jsonTypeName(raw[i])}',
                path: '$path/$key/$i',
              )),
    ];
  }

  /// An optional object whose values must all be strings.
  Map<String, String> stringMap(String key) {
    final raw = optionalObject(key);
    if (raw == null) return const {};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! String) {
        throw FlyFormatException(
          '"$key" values must be strings, got ${_jsonTypeName(value)}',
          path: '$path/$key/${entry.key}',
        );
      }
      out[entry.key] = value;
    }
    return out;
  }
}

String _jsonTypeName(Object? value) {
  if (value == null) return 'null';
  if (value is String) return 'a string';
  if (value is bool) return 'a boolean';
  if (value is int) return 'an integer';
  if (value is num) return 'a number';
  if (value is List) return 'a list';
  if (value is Map) return 'an object';
  return value.runtimeType.toString();
}
