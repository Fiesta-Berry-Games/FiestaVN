import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Downloads a streamed game's assets ahead of need and retains the bytes in
/// memory.
///
/// [orderedAssets] is the prefetch order — the asset plan's story order
/// first, then any remaining manifest files. [prefetchAll] walks that list
/// with a small concurrency window, [fetch] serves a single path cache-first
/// (joining the in-flight download when the prefetcher already started it),
/// and [ensure] gates on a specific set of paths (the first scene's assets).
/// Listeners are notified as each asset lands so hosts can render live
/// progress.
///
/// Progress is byte-accurate when [sizes] covers every ordered asset
/// ([totalBytes] is non-null); otherwise it falls back to file counts
/// ([loadedCount] of [totalCount]). A failure during [prefetchAll] or
/// [ensure] is recorded in [failedPaths] and skipped rather than aborting the
/// run; a later explicit [fetch] retries the download (and clears the record
/// on success), so a transient network error degrades to on-demand loading
/// instead of a dead game.
class StreamedAssetCache extends ChangeNotifier {
  StreamedAssetCache({
    required String baseUrl,
    required List<String> orderedAssets,
    this.sizes,
    http.Client? httpClient,
  }) : baseUrl =
           baseUrl.endsWith('/')
               ? baseUrl.substring(0, baseUrl.length - 1)
               : baseUrl,
       // A set literal preserves first-occurrence order while deduplicating.
       orderedAssets = List.unmodifiable({...orderedAssets}),
       _httpClient = httpClient {
    _tracked = this.orderedAssets.toSet();
    _totalBytes = _sumSizes();
  }

  /// Base URL without a trailing slash; asset [path]s resolve as
  /// `$baseUrl/$path`.
  final String baseUrl;

  /// The prefetch order, deduplicated (first occurrence wins). Progress is
  /// measured against this list; paths fetched on demand that are not listed
  /// here are still cached but do not count toward progress.
  final List<String> orderedAssets;

  /// Byte length per path from the manifest, or null when the manifest
  /// carries no sizes.
  final Map<String, int>? sizes;

  final http.Client? _httpClient;

  late final Set<String> _tracked;
  late final int? _totalBytes;
  final Map<String, Uint8List> _bytes = {};
  final Map<String, Future<Uint8List>> _inFlight = {};
  final Set<String> _failed = {};
  int _loadedTracked = 0;
  int _loadedBytes = 0;
  bool _disposed = false;

  int? _sumSizes() {
    final sizes = this.sizes;
    if (sizes == null) return null;
    var total = 0;
    for (final path in orderedAssets) {
      final size = sizes[path];
      if (size == null) return null; // Sizes must cover every ordered asset.
      total += size;
    }
    return total;
  }

  /// The cached bytes for [path], or null when it has not landed yet.
  Uint8List? bytesFor(String path) => _bytes[path];

  /// Paths whose prefetch (or gate) download failed and was skipped. A later
  /// [fetch] retries and removes the path on success.
  Set<String> get failedPaths => Set.unmodifiable(_failed);

  /// Bytes loaded so far across [orderedAssets], using the manifest size for
  /// each landed path when known (so [progress] reaches exactly 1.0) and the
  /// actual downloaded length otherwise.
  int get loadedBytes => _loadedBytes;

  /// The byte total across [orderedAssets], or null when [sizes] is absent or
  /// missing any ordered path — fall back to [loadedCount]/[totalCount].
  int? get totalBytes => _totalBytes;

  /// How many of [orderedAssets] have landed.
  int get loadedCount => _loadedTracked;

  /// How many assets the cache tracks ([orderedAssets] length).
  int get totalCount => orderedAssets.length;

  /// Overall progress in 0..1: bytes-based when [totalBytes] is known,
  /// count-based otherwise. An empty plan is complete.
  double get progress {
    final total = _totalBytes;
    if (total != null) {
      return total == 0 ? 1 : (_loadedBytes / total).clamp(0, 1).toDouble();
    }
    if (orderedAssets.isEmpty) return 1;
    return _loadedTracked / orderedAssets.length;
  }

  /// Whether every ordered asset has landed.
  bool get isComplete => _loadedTracked >= orderedAssets.length;

  /// Fetches [path] cache-first: returns cached bytes immediately, joins an
  /// in-flight download when one is running, and otherwise downloads and
  /// stores the bytes. Throws on network/HTTP failure (the caller decides
  /// whether that is fatal); a successful retry clears the path from
  /// [failedPaths].
  Future<Uint8List> fetch(String path) {
    final cached = _bytes[path];
    if (cached != null) return Future<Uint8List>.value(cached);
    final pending = _inFlight[path];
    if (pending != null) return pending;
    final download = _download(path);
    _inFlight[path] = download;
    return download;
  }

  /// Awaits the given [paths] — the first-scene gate. Each path either lands
  /// or has its failure recorded in [failedPaths]; the future never throws,
  /// so a missing gate asset degrades to on-demand loading rather than
  /// blocking the game forever.
  Future<void> ensure(Iterable<String> paths) async {
    await Future.wait([
      for (final path in paths)
        fetch(path).then<void>(
          (_) {},
          onError: (Object _) => _recordFailure(path),
        ),
    ]);
  }

  /// Prefetches every ordered asset, in order, [concurrency] downloads at a
  /// time. Failures are recorded in [failedPaths] and skipped so one bad
  /// asset cannot kill the background run.
  Future<void> prefetchAll({int concurrency = 3}) async {
    var next = 0;
    Future<void> worker() async {
      while (next < orderedAssets.length && !_disposed) {
        final path = orderedAssets[next++];
        if (_bytes.containsKey(path)) continue;
        try {
          await fetch(path);
        } on Object {
          _recordFailure(path);
        }
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i += 1) worker()]);
  }

  Future<Uint8List> _download(String path) async {
    try {
      final uri = Uri.parse('$baseUrl/$path');
      final client = _httpClient;
      final response =
          client == null ? await http.get(uri) : await client.get(uri);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'GET $uri failed with HTTP ${response.statusCode}',
          uri,
        );
      }
      final bytes = response.bodyBytes;
      _store(path, bytes);
      return bytes;
    } finally {
      _inFlight.remove(path);
    }
  }

  void _store(String path, Uint8List bytes) {
    if (_disposed) return;
    if (_bytes.containsKey(path)) return;
    _bytes[path] = bytes;
    _failed.remove(path);
    if (_tracked.contains(path)) {
      _loadedTracked += 1;
      _loadedBytes += sizes?[path] ?? bytes.length;
    }
    notifyListeners();
  }

  void _recordFailure(String path) {
    if (_disposed) return;
    if (_failed.add(path)) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// An [http.Client] that answers GET requests under the cache's base URL
/// through [StreamedAssetCache.fetch].
///
/// This is how streamed audio stays cache-first without splitting playback
/// across two backends: `RenPyUrlAudioPlayback` keeps owning all channel and
/// mixer state and issues plain HTTP GETs, while this adapter serves them
/// from memory when the prefetcher already has the track, joins the in-flight
/// download when it is mid-transfer, and otherwise fetches through the cache
/// so the bytes are retained for the next play.
class StreamedAssetCacheHttpClient extends http.BaseClient {
  StreamedAssetCacheHttpClient(this.cache);

  final StreamedAssetCache cache;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // The playback builds URLs by joining the base with the raw asset path;
    // decode so paths with spaces map back to their manifest spelling.
    final url = Uri.decodeFull(request.url.toString());
    final prefix = '${cache.baseUrl}/';
    if (request.method != 'GET' || !url.startsWith(prefix)) {
      throw http.ClientException(
        'StreamedAssetCacheHttpClient only serves GETs under $prefix',
        request.url,
      );
    }
    final bytes = await cache.fetch(url.substring(prefix.length));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      contentLength: bytes.length,
      request: request,
    );
  }
}
