import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads [contents] as [filename] using the Blob + anchor-click pattern.
Future<void> saveTextFile(String filename, String contents) async {
  _downloadBlob(
    filename,
    web.Blob(
      <JSAny>[contents.toJS].toJS,
      web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
    ),
  );
}

/// Downloads [bytes] as [filename] using the Blob + anchor-click pattern.
Future<void> saveBinaryFile(String filename, Uint8List bytes) async {
  _downloadBlob(
    filename,
    web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/zip'),
    ),
  );
}

void _downloadBlob(String filename, web.Blob blob) {
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
