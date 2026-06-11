import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:renpy_core/renpy_core.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_writer/renpy_writer.dart';

import 'src/streamed_asset_cache.dart';

/// Plays a game whose files are streamed over HTTP instead of bundled.
///
/// [baseUrl] is the directory that holds a `fly_manifest.json` (see
/// `renpy_writer`'s `FlyStreamManifest` / `fly_stream` CLI). Only the
/// manifest and the `.fly` script are downloaded up front. Per the streaming
/// policy, only migrated `.fly` games can stream — the manifest decoder
/// rejects `.rpy` scripts with an explanation.
///
/// Loading strategy: the script is parsed once and turned into a
/// `RenPyAssetPlan` (assets per top-level label, in story order). A
/// [StreamedAssetCache] prefetches every asset in plan order in the
/// background, while the screen gates only on the FIRST segment's assets —
/// showing a determinate, byte-accurate progress view — before starting the
/// controller. Images are served cache-first ([MemoryImage]) with a
/// [NetworkImage] fallback for anything the prefetcher has not reached yet.
///
/// Audio design: rather than splitting playback across a bytes backend and a
/// URL backend (which would split per-channel/mixer state between two
/// engines), a single [RenPyUrlAudioPlayback] owns all audio state and its
/// HTTP client is a [StreamedAssetCacheHttpClient] — every track GET is
/// answered from the cache when the bytes are already in memory, joins the
/// in-flight prefetch download when one is running, and otherwise fetches
/// through the cache so the bytes are kept for replays.
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
  /// null, tracks stream from [baseUrl] through the asset cache.
  final RenPyAudioPlayback? audioPlayback;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;

  @override
  State<StreamedGameScreen> createState() => _StreamedGameScreenState();
}

class _StreamedGameScreenState extends State<StreamedGameScreen> {
  RenPyFlutterController? _controller;
  RenPyAudioPlayback? _ownedAudioPlayback;
  RenPyPreferenceStore? _preferenceStore;
  StreamedAssetCache? _cache;
  RenPyAssetPlan? _plan;
  List<String> _gateAssets = const [];
  Map<String, int>? _sizes;
  bool _gateDone = false;
  bool _streamingChip = false;
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

      final slash = manifest.script.lastIndexOf('/');
      final gameRoot = slash < 0 ? '' : manifest.script.substring(0, slash);
      final manifestFiles = manifest.files.toSet();

      // Parse the emitted source once — the same text the controller will
      // load — and build the prefetch plan from it.
      final parsed = RenPyParser().parse(source, manifest.script).script;
      final resolver = RenPyImageResolver.fromScript(
        parsed,
        assetRoot: gameRoot,
        availableAssets: manifestFiles,
      );
      final plan = RenPyAssetPlan.fromScript(
        parsed,
        resolver: resolver,
        availableAssets: manifestFiles,
        gameRoot: gameRoot,
      );

      // Prefetch order: the plan's story order, then any manifest files the
      // plan could not attribute statically (the script itself is already
      // downloaded and excluded).
      final ordered = plan.assetsFromSegment(0);
      final orderedSet = ordered.toSet();
      final cache = StreamedAssetCache(
        baseUrl: _base,
        orderedAssets: [
          ...ordered,
          for (final file in manifest.files)
            if (file != manifest.script && !orderedSet.contains(file)) file,
        ],
        sizes: manifest.sizes,
        httpClient: widget.httpClient,
      );
      cache.addListener(_onCacheChanged);
      unawaited(cache.prefetchAll());

      final gateAssets =
          plan.segments.isEmpty ? const <String>[] : plan.segments.first.assets;

      if (!mounted) {
        cache.dispose();
        return;
      }
      setState(() {
        _cache = cache;
        _plan = plan;
        _gateAssets = gateAssets;
        _sizes = manifest.sizes;
        _source = source;
        _scriptPath = manifest.script;
        _gameRoot = gameRoot;
        _availableAssets = manifestFiles;
        _name = manifest.name;
      });

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
      controller.addListener(_onControllerChanged);
      widget.onControllerCreated?.call(controller);

      setState(() {
        _controller = controller;
        _preferenceStore = preferenceStore;
        if (widget.audioPlayback == null) {
          _ownedAudioPlayback = RenPyUrlAudioPlayback(
            baseUrl: '$_base/',
            httpClient: StreamedAssetCacheHttpClient(cache),
          );
        }
      });

      // FIRST-SCENE GATE: wait for the opening segment's assets (each lands
      // or fails once — a failed asset degrades to on-demand loading instead
      // of blocking forever), then start the game.
      await cache.ensure(gateAssets);
      if (!mounted) return;
      setState(() => _gateDone = true);
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

  void _onCacheChanged() {
    if (!mounted) return;
    setState(() {}); // Progress bars and cache-first images may update.
    _updateChip();
  }

  void _onControllerChanged() => _updateChip();

  /// Shows the non-blocking "Streaming…" chip while the current label's
  /// segment still has uncached assets (NetworkImage covers the misses).
  void _updateChip() {
    if (!mounted) return;
    final plan = _plan;
    final cache = _cache;
    final label = _controller?.currentLabel;
    var pending = false;
    if (plan != null && cache != null && label != null) {
      final index = plan.segmentIndexForLabel(label);
      if (index >= 0) {
        pending = plan.segments[index].assets.any(
          (asset) => cache.bytesFor(asset) == null,
        );
      }
    }
    if (pending != _streamingChip) {
      setState(() => _streamingChip = pending);
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
    final cache = _cache;
    if (cache != null) {
      final bytes = cache.bytesFor(assetPath);
      if (bytes != null) return MemoryImage(bytes);
      // Opportunistically pull the miss into the cache so revisits (and the
      // soft scene indicator) hit memory; the NetworkImage below covers the
      // current paint.
      cache.fetch(assetPath).ignore();
    }
    return NetworkImage('$_base/$assetPath');
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _cache?.removeListener(_onCacheChanged);
    _cache?.dispose();
    _ownedAudioPlayback?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// Gate progress over the first segment only: bytes-based when the
  /// manifest sizes cover every gated asset, count-based otherwise.
  ({double progress, String label}) _gateStatus() {
    final cache = _cache;
    final paths = _gateAssets;
    final sizes = _sizes;
    var sizesKnown = sizes != null && paths.isNotEmpty;
    var totalBytes = 0;
    var loadedBytes = 0;
    var loadedCount = 0;
    for (final path in paths) {
      final size = sizes?[path];
      if (size == null) sizesKnown = false;
      final loaded = cache?.bytesFor(path) != null;
      if (loaded) loadedCount += 1;
      if (size != null) {
        totalBytes += size;
        if (loaded) loadedBytes += size;
      }
    }
    if (sizesKnown) {
      final progress = totalBytes == 0 ? 1.0 : loadedBytes / totalBytes;
      return (
        progress: progress,
        label: 'Streamed · ${_mb(loadedBytes)} / ${_mb(totalBytes)} MB',
      );
    }
    final progress = paths.isEmpty ? 1.0 : loadedCount / paths.length;
    return (
      progress: progress,
      label: 'Streamed · $loadedCount/${paths.length} files',
    );
  }

  static String _mb(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);

  Widget _gateView(BuildContext context, String title) {
    final status = _gateStatus();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(
                key: const ValueKey('streamed-progress'),
                value: status.progress,
              ),
              const SizedBox(height: 12),
              Text(status.label),
              const SizedBox(height: 24),
              TextButton(
                key: const ValueKey('streamed-cancel'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerView(BuildContext context) {
    final controller = _controller!;
    final cache = _cache!;
    final screenSize = RenPyScreenSize.fromScriptSource(_source!);
    return Stack(
      children: [
        RenPyPlayer(
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
        ),
        // Thin overall-prefetch trickle along the top edge until everything
        // has landed.
        if (!cache.isComplete)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: const ValueKey('streamed-trickle'),
              value: cache.progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          ),
        // Soft, non-blocking indicator while the current scene's assets are
        // still streaming in (the game keeps playing; NetworkImage covers
        // any miss).
        if (_streamingChip)
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              key: const ValueKey('streamed-chip'),
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Streaming…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _name ?? widget.title ?? 'Streamed game';
    final error = _error;

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
    } else if (_source == null || _cache == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_gateDone || _controller == null) {
      body = _gateView(context, title);
    } else {
      body = _playerView(context);
    }

    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}
