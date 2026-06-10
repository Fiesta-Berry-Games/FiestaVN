import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_writer/renpy_writer.dart';

/// Plays a game whose files are streamed over HTTP instead of bundled.
///
/// [baseUrl] is the directory that holds a `fly_manifest.json` (see
/// `renpy_writer`'s `FlyStreamManifest` / `fly_stream` CLI). Only the
/// manifest and the `.fly` script are downloaded up front; images and audio
/// are fetched lazily as the story references them. Per the streaming
/// policy, only migrated `.fly` games can stream — the manifest decoder
/// rejects `.rpy` scripts with an explanation.
class StreamedGameScreen extends StatefulWidget {
  const StreamedGameScreen({
    super.key,
    required this.baseUrl,
    this.title,
    this.audioPlayback,
    this.onControllerCreated,
    this.httpClient,
  });

  final String baseUrl;
  final String? title;

  /// HTTP client override so tests can serve a fake game.
  final http.Client? httpClient;

  /// Audio backend override (tests inject [RenPyNoOpAudioPlayback]); when
  /// null, tracks stream from [baseUrl] like every other asset.
  final RenPyAudioPlayback? audioPlayback;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;

  @override
  State<StreamedGameScreen> createState() => _StreamedGameScreenState();
}

class _StreamedGameScreenState extends State<StreamedGameScreen> {
  RenPyFlutterController? _controller;
  RenPyAudioPlayback? _ownedAudioPlayback;
  RenPyPreferenceStore? _preferenceStore;
  String? _source;
  String? _scriptPath;
  String _gameRoot = 'game';
  Set<String> _availableAssets = const {};
  String? _name;
  Object? _error;

  String get _base {
    final url = widget.baseUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<String> _fetchText(String url) async {
    final client = widget.httpClient;
    final uri = Uri.parse(url);
    final response =
        client == null ? await http.get(uri) : await client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('GET $url failed with HTTP ${response.statusCode}');
    }
    return response.body;
  }

  Future<void> _bootstrap() async {
    try {
      final manifest = FlyStreamManifest.decode(
        await _fetchText('$_base/${FlyStreamManifest.fileName}'),
      );
      final flyText = await _fetchText('$_base/${manifest.script}');
      final script = const FlyCodec().decodeFromString(
        flyText,
        filename: manifest.script,
      );
      final source = const RenPyEmitter().emitScript(script);

      final persistentStore =
          await RenPySharedPreferencesPersistentStore.create(
            key: 'renfly.persistent.${Uri.encodeComponent(_base)}',
          );
      final snapshotStore = await RenPySharedPreferencesSnapshotStore.create(
        key: 'renfly.snapshot.${Uri.encodeComponent(_base)}',
      );
      final slotStore = await RenPySharedPreferencesSnapshotSlotStore.create(
        keyPrefix: 'renfly.slot.${Uri.encodeComponent(_base)}',
      );
      final preferenceStore =
          await RenPySharedPreferencesPreferenceStore.create(
            key: 'renfly.preferences.${Uri.encodeComponent(_base)}',
          );
      if (!mounted) return;

      final controller = RenPyFlutterController(
        persistentStore: persistentStore,
        snapshotStore: snapshotStore,
        slotStore: slotStore,
      );
      widget.onControllerCreated?.call(controller);

      final slash = manifest.script.lastIndexOf('/');
      setState(() {
        _controller = controller;
        _preferenceStore = preferenceStore;
        _source = source;
        _scriptPath = manifest.script;
        _gameRoot = slash < 0 ? '' : manifest.script.substring(0, slash);
        _availableAssets = manifest.files.toSet();
        _name = manifest.name;
        if (widget.audioPlayback == null) {
          _ownedAudioPlayback = RenPyUrlAudioPlayback(baseUrl: '$_base/');
        }
      });
      // Load after the frame so the player's layers are mounted and receive
      // the initial scene/show events.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadController();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _loadController() {
    final controller = _controller;
    final source = _source;
    if (controller == null || source == null) return;
    try {
      controller.load(
        source,
        filename: _scriptPath ?? 'streamed.fly',
        gameRoot: _gameRoot,
        availableAssets: _availableAssets,
      );
    } catch (error) {
      controller.value = RenPyError(error.toString());
    }
  }

  ImageProvider<Object> _imageProvider(String assetPath) {
    return NetworkImage('$_base/$assetPath');
  }

  @override
  void dispose() {
    _ownedAudioPlayback?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _name ?? widget.title ?? 'Streamed game';
    final error = _error;
    final controller = _controller;

    final Widget body;
    if (error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not stream this game: $error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (controller == null || _source == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final screenSize = RenPyScreenSize.fromScriptSource(_source!);
      body = RenPyPlayer(
        controller: controller,
        backgroundColor: Colors.grey.shade900,
        onRestart: _loadController,
        gameRoot: _gameRoot,
        screenSize: screenSize,
        audioPlayback: widget.audioPlayback ?? _ownedAudioPlayback,
        preferenceStore: _preferenceStore,
        dialogueImageProvider: _imageProvider,
        screenImageProvider: _imageProvider,
        imageLayerBuilder: (context, controller) {
          return RenPyImageLayer(
            controller: controller,
            imageProvider: _imageProvider,
            screenSize: screenSize ?? RenPyScreenSize.fallback,
            atlResolver: controller.resolveAtl,
          );
        },
      );
    }

    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}
