import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:renfly_player/src/streamed_asset_cache.dart';

const _base = 'https://example.test/games/demo';

String _pathOf(http.Request request) =>
    Uri.decodeFull(request.url.toString()).substring('$_base/'.length);

void main() {
  test('prefetchAll downloads in plan order and notifies as assets land', () async {
    final assets = ['a.png', 'b.png', 'c.png', 'd.png', 'e.png'];
    final sizes = {
      for (final (index, asset) in assets.indexed) asset: (index + 1) * 10,
    };
    final requested = <String>[];
    final client = MockClient((request) async {
      final path = _pathOf(request);
      requested.add(path);
      return http.Response.bytes(List<int>.filled(sizes[path]!, 1), 200);
    });
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: assets,
      sizes: sizes,
      httpClient: client,
    );
    var notifications = 0;
    cache.addListener(() => notifications += 1);

    expect(cache.totalBytes, 150);
    expect(cache.totalCount, 5);
    expect(cache.progress, 0);
    expect(cache.isComplete, isFalse);

    await cache.prefetchAll();

    expect(requested, assets, reason: 'requests start in plan order');
    expect(cache.isComplete, isTrue);
    expect(cache.progress, 1);
    expect(cache.loadedBytes, 150);
    expect(cache.loadedCount, 5);
    expect(notifications, 5, reason: 'one notification per landed asset');
    expect(cache.bytesFor('c.png'), isNotNull);
  });

  test('fetch joins an in-flight download', () async {
    var calls = 0;
    final gate = Completer<void>();
    final client = MockClient((request) async {
      calls += 1;
      await gate.future;
      return http.Response.bytes(const [1, 2, 3], 200);
    });
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['a.png'],
      httpClient: client,
    );

    final first = cache.fetch('a.png');
    final second = cache.fetch('a.png');
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(calls, 1, reason: 'the second fetch joins the first download');
    expect(results[0], results[1]);
    expect(cache.bytesFor('a.png'), isNotNull);

    await cache.fetch('a.png');
    expect(calls, 1, reason: 'a later fetch is a pure cache hit');
  });

  test('prefetch failures are skipped, recorded, and retried on fetch', () async {
    var failing = true;
    final client = MockClient((request) async {
      final path = _pathOf(request);
      if (path == 'b.png' && failing) return http.Response('boom', 500);
      return http.Response.bytes(const [1], 200);
    });
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['a.png', 'b.png', 'c.png'],
      httpClient: client,
    );

    await cache.prefetchAll(); // A failed asset must not kill the run.

    expect(cache.failedPaths, {'b.png'});
    expect(cache.bytesFor('b.png'), isNull);
    expect(cache.loadedCount, 2);
    expect(cache.isComplete, isFalse);

    failing = false;
    await cache.fetch('b.png');

    expect(cache.failedPaths, isEmpty);
    expect(cache.bytesFor('b.png'), isNotNull);
    expect(cache.isComplete, isTrue);
  });

  test('progress is bytes-based when sizes cover every ordered asset', () async {
    final sizes = {'big.png': 90, 'small.png': 10};
    final client = MockClient((request) async {
      return http.Response.bytes(
        List<int>.filled(sizes[_pathOf(request)]!, 1),
        200,
      );
    });
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['big.png', 'small.png'],
      sizes: sizes,
      httpClient: client,
    );

    expect(cache.totalBytes, 100);
    await cache.fetch('small.png');
    expect(cache.progress, closeTo(0.1, 1e-9));
    await cache.fetch('big.png');
    expect(cache.progress, 1);

    // Sizes that miss any ordered asset disable byte totals entirely.
    final partial = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['big.png', 'small.png'],
      sizes: const {'big.png': 90},
      httpClient: client,
    );
    expect(partial.totalBytes, isNull);
  });

  test('progress falls back to counts when the manifest lacks sizes', () async {
    final client = MockClient(
      (request) async => http.Response.bytes(const [1, 2], 200),
    );
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['a.png', 'b.png'],
      httpClient: client,
    );

    expect(cache.totalBytes, isNull);
    expect(cache.totalCount, 2);
    expect(cache.progress, 0);

    await cache.fetch('a.png');
    expect(cache.loadedCount, 1);
    expect(cache.progress, 0.5);
    expect(cache.loadedBytes, 2, reason: 'actual length when sizes unknown');

    await cache.fetch('b.png');
    expect(cache.progress, 1);
    expect(cache.isComplete, isTrue);
  });

  test('ensure awaits the gate set and records failures without throwing', () async {
    final client = MockClient((request) async {
      if (_pathOf(request) == 'missing.png') {
        return http.Response('nope', 404);
      }
      return http.Response.bytes(const [9], 200);
    });
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['a.png', 'missing.png'],
      httpClient: client,
    );

    await cache.ensure(const ['a.png', 'missing.png']);

    expect(cache.bytesFor('a.png'), isNotNull);
    expect(cache.failedPaths, {'missing.png'});
  });

  test('StreamedAssetCacheHttpClient serves GETs through the cache', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response.bytes(const [5, 5, 5], 200);
    });
    final cache = StreamedAssetCache(
      baseUrl: _base,
      orderedAssets: const ['music/track.opus'],
      httpClient: client,
    );
    final adapter = StreamedAssetCacheHttpClient(cache);

    final response = await adapter.get(Uri.parse('$_base/music/track.opus'));
    expect(response.statusCode, 200);
    expect(response.bodyBytes, const [5, 5, 5]);
    expect(cache.bytesFor('music/track.opus'), isNotNull);
    expect(calls, 1, reason: 'the miss fetched through the cache');

    await adapter.get(Uri.parse('$_base/music/track.opus'));
    expect(calls, 1, reason: 'the second play is a cache hit');
  });
}
