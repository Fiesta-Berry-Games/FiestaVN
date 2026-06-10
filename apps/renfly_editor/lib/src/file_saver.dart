import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart'
    as platform;

/// Saves [contents] as a text file named [filename].
///
/// On the web this triggers a browser download; on IO platforms it shows a
/// save dialog and writes the file to the chosen path.
Future<void> saveTextFile(String filename, String contents) {
  return platform.saveTextFile(filename, contents);
}
