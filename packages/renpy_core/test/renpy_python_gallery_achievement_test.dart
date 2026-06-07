import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for inert placeholder builtins (Achievement, Gallery, GalleryAlbum,
/// GalleryImage, ZoomGallery) and the renpy.register_sl_displayable no-op.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope([Map<String, Object?>? store]) => RenPyMapScope(
        store: store ?? <String, Object?>{},
        persistent: <String, Object?>{},
      );

  group('Achievement / Gallery placeholders', () {
    test('Achievement evaluates as inert placeholder', () {
      final s = scope();
      final result = evaluator.evaluate("Achievement('test')", s);
      expect(result, isNotNull);
      expect(result.toString(), contains('Achievement'));
    });

    test('Gallery evaluates as inert placeholder', () {
      final s = scope();
      final result = evaluator.evaluate('Gallery()', s);
      expect(result, isNotNull);
      expect(result.toString(), contains('Gallery'));
    });

    test('GalleryAlbum evaluates as inert placeholder', () {
      final s = scope();
      final result = evaluator.evaluate("GalleryAlbum('album1')", s);
      expect(result, isNotNull);
      expect(result.toString(), contains('GalleryAlbum'));
    });

    test('GalleryImage evaluates as inert placeholder', () {
      final s = scope();
      final result = evaluator.evaluate("GalleryImage('img')", s);
      expect(result, isNotNull);
      expect(result.toString(), contains('GalleryImage'));
    });

    test('ZoomGallery evaluates as inert placeholder', () {
      final s = scope();
      final result = evaluator.evaluate('ZoomGallery()', s);
      expect(result, isNotNull);
      expect(result.toString(), contains('ZoomGallery'));
    });

    test('Achievement method calls return null', () {
      final s = scope();
      executor.execute("a = Achievement('test')\na.grant()", s);
      // Should not throw.
    });

    test('Gallery method calls return null', () {
      final s = scope();
      executor.execute('g = Gallery()\ng.button("img")', s);
      // Should not throw.
    });
  });

  group('renpy.register_sl_displayable no-op', () {
    test('register_sl_displayable returns a chainable placeholder', () {
      final s = scope();
      final result = evaluator.evaluate(
        "renpy.register_sl_displayable('foo', None)",
        s,
      );
      // Returns a chainable placeholder (not null) so `.add_property(...)`
      // calls on the result evaluate instead of failing on null.
      expect(result, isNotNull);
    });
  });

  group('gui.preference no-op', () {
    test('gui.preference returns null without throwing', () {
      final s = scope();
      final result = evaluator.evaluate(
        'gui.preference("text speed", 0)',
        s,
      );
      expect(result, isNull);
    });
  });
}
