import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Shows a save dialog and writes [contents] to the chosen path.
Future<void> saveTextFile(String filename, String contents) async {
  final path = await _pickSavePath(filename);
  if (path == null) return;
  await File(path).writeAsString(contents);
}

/// Shows a save dialog and writes [bytes] to the chosen path.
Future<void> saveBinaryFile(String filename, Uint8List bytes) async {
  final path = await _pickSavePath(filename);
  if (path == null) return;
  await File(path).writeAsBytes(bytes);
}

Future<String?> _pickSavePath(String filename) {
  return FilePicker.saveFile(dialogTitle: 'Save $filename', fileName: filename);
}
