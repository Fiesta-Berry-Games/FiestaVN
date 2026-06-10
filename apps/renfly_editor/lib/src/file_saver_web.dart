import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [contents] as [filename] using the Blob + anchor-click pattern.
Future<void> saveTextFile(String filename, String contents) async {
  final blob = web.Blob(
    <JSAny>[contents.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.HTMLAnchorElement()
        ..href = url
        ..download = filename
        ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
