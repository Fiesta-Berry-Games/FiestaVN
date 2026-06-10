import 'dart:typed_data';

Future<void> saveTextFile(String filename, String contents) async {
  throw UnsupportedError('Saving files is not supported on this platform.');
}

Future<void> saveBinaryFile(String filename, Uint8List bytes) async {
  throw UnsupportedError('Saving files is not supported on this platform.');
}
