// The launcher gates entry to the game on the Spine assets being loaded:
// tapping the tile fetches the deduped .atlas, .skel, and atlas page .png
// behind a determinate progress bar, navigation only happens once all loads
// complete, failures surface a retry button, and a second launch skips the
// gate entirely (the preloader remembers success; rootBundle keeps bytes).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renspine/main.dart';
import 'package:renspine/spine_preloader.dart';

const _atlas = 'assets/chibi-stickers/export/chibi-stickers.atlas';
const _skel = 'assets/chibi-stickers/export/chibi-stickers-pro.skel';
const _png = 'assets/chibi-stickers/export/chibi-stickers-pro.png';

/// A minimal atlas: the page image name on the first line, as in the real
/// export, so the preloader discovers the .png it still has to fetch.
const _atlasText = 'chibi-stickers-pro.png\nsize:2047,501\nfilter:Linear\n';

ByteData _bytes(String contents) =>
    ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)));

/// Completer-backed [AssetLoader] fake: every request stays pending until
/// the test completes (or fails) it, so gating and progress are observable.
class _FakeAssetLoader {
  final completers = <String, Completer<ByteData>>{};
  final requests = <String>[];

  Future<ByteData> call(String key) {
    requests.add(key);
    final completer = Completer<ByteData>();
    completers[key] = completer;
    return completer.future;
  }

  void complete(String key, [String contents = '']) =>
      completers[key]!.complete(_bytes(contents));

  void fail(String key) =>
      completers[key]!.completeError(Exception('network down'));
}

Widget _app(_FakeAssetLoader loader) {
  return FiestaVNApp(
    loadAsset: loader.call,
    gameScreenBuilder:
        (assetPath, title) => Scaffold(
          key: const ValueKey('fake-game-screen'),
          appBar: AppBar(title: Text(title)),
          body: Text(assetPath),
        ),
  );
}

final _tile = find.byKey(const ValueKey('fiesta-skit-tile'));
final _progress = find.byKey(const ValueKey('spine-preload-progress'));
final _retry = find.byKey(const ValueKey('spine-preload-retry'));
final _gameScreen = find.byKey(const ValueKey('fake-game-screen'));

void main() {
  testWidgets('tile shows progress and only navigates once assets load', (
    tester,
  ) async {
    final loader = _FakeAssetLoader();
    await tester.pumpWidget(_app(loader));
    expect(_progress, findsNothing);

    await tester.tap(_tile);
    await tester.pump();

    // Gate is up: progress visible, no navigation, only the (deduped) atlas
    // requested so far even though three characters share it.
    expect(_progress, findsOneWidget);
    expect(_gameScreen, findsNothing);
    expect(loader.requests, [_atlas]);
    expect(tester.widget<ElevatedButton>(_tile).onPressed, isNull);

    loader.complete(_atlas, _atlasText);
    await tester.pump();
    expect(find.text('Loading characters… 1/3'), findsOneWidget);
    expect(_gameScreen, findsNothing);
    expect(loader.requests, [_atlas, _skel]);

    loader.complete(_skel);
    await tester.pump();
    expect(find.text('Loading characters… 2/3'), findsOneWidget);
    expect(_gameScreen, findsNothing);
    expect(loader.requests, [_atlas, _skel, _png]);

    loader.complete(_png);
    await tester.pumpAndSettle();
    expect(_gameScreen, findsOneWidget);
    expect(find.text('Fiesta Skit'), findsOneWidget);
  });

  testWidgets('a failed load shows retry, and retry can succeed', (
    tester,
  ) async {
    final loader = _FakeAssetLoader();
    await tester.pumpWidget(_app(loader));

    await tester.tap(_tile);
    await tester.pump();
    loader.complete(_atlas, _atlasText);
    await tester.pump();
    loader.fail(_skel);
    await tester.pump();

    expect(_gameScreen, findsNothing);
    expect(_progress, findsNothing);
    expect(_retry, findsOneWidget);

    await tester.tap(_retry);
    await tester.pump();
    expect(_progress, findsOneWidget);
    expect(_retry, findsNothing);

    loader.complete(_atlas, _atlasText);
    await tester.pump();
    loader.complete(_skel);
    await tester.pump();
    loader.complete(_png);
    await tester.pumpAndSettle();
    expect(_gameScreen, findsOneWidget);
  });

  testWidgets('a second launch skips the gate and loads nothing new', (
    tester,
  ) async {
    final loader = _FakeAssetLoader();
    await tester.pumpWidget(_app(loader));

    await tester.tap(_tile);
    await tester.pump();
    loader.complete(_atlas, _atlasText);
    await tester.pump();
    loader.complete(_skel);
    await tester.pump();
    loader.complete(_png);
    await tester.pumpAndSettle();
    expect(_gameScreen, findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    final requestsAfterFirstLaunch = loader.requests.length;

    await tester.tap(_tile);
    await tester.pumpAndSettle();
    expect(_gameScreen, findsOneWidget);
    expect(_progress, findsNothing);
    expect(loader.requests.length, requestsAfterFirstLaunch);
  });

  test('preloader dedupes shared assets across characters', () async {
    final loader = _FakeAssetLoader();
    final preloader = SpineAssetPreloader(
      characters: kSpineCharacters,
      loadAsset: loader.call,
    );
    addTearDown(preloader.dispose);

    final done = preloader.ensureLoaded();
    expect(preloader.isLoading, isTrue);
    loader.complete(_atlas, _atlasText);
    await Future<void>.delayed(Duration.zero);
    loader.complete(_skel);
    await Future<void>.delayed(Duration.zero);
    loader.complete(_png);
    await done;

    expect(preloader.isLoaded, isTrue);
    expect(preloader.progress, 1.0);
    // Three characters, one shared skeleton: exactly three fetches.
    expect(loader.requests, [_atlas, _skel, _png]);

    // A second call completes synchronously without new requests.
    await preloader.ensureLoaded();
    expect(loader.requests, hasLength(3));
  });
}
