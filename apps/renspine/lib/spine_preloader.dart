import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:renpy_spine/renpy_spine.dart' show SpineCharacter;

/// Loads the bytes of one bundled asset. Defaults to [rootBundle.load];
/// tests inject a completer-backed fake to control timing and failures.
typedef AssetLoader = Future<ByteData> Function(String key);

/// Preloads the Spine assets a set of [SpineCharacter]s needs before the
/// game screen opens: each distinct `.atlas`, each distinct `.skel`, and
/// every atlas page image (`.png` etc.) the atlas files reference.
///
/// On web these loads are network fetches, so warming them here means the
/// game never shows an empty stage while skeletons stream in. Progress is
/// exposed as a per-file count ([loadedCount] of [totalCount]) and the
/// success bit sticks ([isLoaded]), so a second launch skips the gate —
/// [rootBundle] keeps the bytes cached.
class SpineAssetPreloader extends ChangeNotifier {
  SpineAssetPreloader({
    required List<SpineCharacter> characters,
    AssetLoader? loadAsset,
  })  : _loadAsset = loadAsset ?? rootBundle.load,
        // Characters share skeletons (they are skins of one export), so
        // dedupe by asset path before counting or fetching anything.
        _atlasAssets =
            {for (final c in characters) c.atlasAsset}.toList(growable: false),
        _skeletonAssets = {for (final c in characters) c.skeletonAsset}
            .toList(growable: false);

  final AssetLoader _loadAsset;
  final List<String> _atlasAssets;
  final List<String> _skeletonAssets;

  Future<void>? _inFlight;
  bool _isLoaded = false;
  bool _disposed = false;
  Object? _error;
  int _loadedCount = 0;
  int _totalCount = 0;

  /// Whether every asset has been loaded successfully at least once.
  bool get isLoaded => _isLoaded;

  /// Whether a load pass is currently running.
  bool get isLoading => _inFlight != null;

  /// The error that aborted the last load pass, if any.
  Object? get error => _error;

  /// Files fetched so far in the current (or last) pass.
  int get loadedCount => _loadedCount;

  /// Total files in the current pass. Grows once an atlas is parsed and its
  /// page images become known.
  int get totalCount => _totalCount;

  /// Determinate progress in `[0, 1]`, or null before the first pass starts.
  double? get progress => _totalCount == 0 ? null : _loadedCount / _totalCount;

  /// Loads all assets, reporting progress via [ChangeNotifier]. Completes
  /// immediately if a previous pass succeeded; joins the in-flight pass if
  /// one is running. Throws (and records [error]) if any fetch fails, after
  /// which calling this again retries from scratch.
  Future<void> ensureLoaded() {
    if (_isLoaded) return Future.value();
    return _inFlight ??= _load();
  }

  Future<void> _load() async {
    _error = null;
    _loadedCount = 0;
    _totalCount = _atlasAssets.length + _skeletonAssets.length;
    _notify();
    try {
      // Atlases first: they name the page images that still need fetching.
      final pageAssets = <String>{};
      for (final atlas in _atlasAssets) {
        final bytes = await _loadAsset(atlas);
        pageAssets.addAll(_atlasPageAssets(atlas, bytes));
        _totalCount =
            _atlasAssets.length + _skeletonAssets.length + pageAssets.length;
        _loadedCount++;
        _notify();
      }
      for (final asset in [..._skeletonAssets, ...pageAssets]) {
        await _loadAsset(asset);
        _loadedCount++;
        _notify();
      }
      _isLoaded = true;
    } catch (e) {
      _error = e;
      rethrow;
    } finally {
      _inFlight = null;
      _notify();
    }
  }

  /// The page image asset paths referenced by an atlas, resolved against the
  /// atlas file's own directory. In the Spine atlas text format page names
  /// are the only lines ending in an image extension.
  static Iterable<String> _atlasPageAssets(String atlasAsset, ByteData data) {
    final text = utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      allowMalformed: true,
    );
    final slash = atlasAsset.lastIndexOf('/');
    final dir = slash == -1 ? '' : atlasAsset.substring(0, slash + 1);
    return [
      for (final line in LineSplitter.split(text))
        if (_isImageFile(line.trim())) '$dir${line.trim()}',
    ];
  }

  static bool _isImageFile(String line) =>
      line.endsWith('.png') ||
      line.endsWith('.jpg') ||
      line.endsWith('.jpeg') ||
      line.endsWith('.webp');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
