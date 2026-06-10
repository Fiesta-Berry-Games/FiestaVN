import 'dart:typed_data';

import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart'
    as platform;

/// Signature of [saveTextFile], so widgets can accept an injectable saver
/// (tests substitute an in-memory fake).
typedef SaveTextFile = Future<void> Function(String filename, String contents);

/// Signature of [saveBinaryFile], so widgets can accept an injectable saver
/// (tests substitute an in-memory fake).
typedef SaveBinaryFile = Future<void> Function(String filename, Uint8List bytes);

/// Saves [contents] as a text file named [filename].
///
/// On the web this triggers a browser download; on IO platforms it shows a
/// save dialog and writes the file to the chosen path.
Future<void> saveTextFile(String filename, String contents) {
  return platform.saveTextFile(filename, contents);
}

/// Saves [bytes] as a binary file named [filename].
///
/// On the web this triggers a browser download; on IO platforms it shows a
/// save dialog and writes the file to the chosen path.
Future<void> saveBinaryFile(String filename, Uint8List bytes) {
  return platform.saveBinaryFile(filename, bytes);
}
