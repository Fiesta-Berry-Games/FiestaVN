import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Shows a save dialog and writes [contents] to the chosen path.
Future<void> saveTextFile(String filename, String contents) async {
  final path = await FilePicker.saveFile(
    dialogTitle: 'Save $filename',
    fileName: filename,
  );
  if (path == null) return;
  await File(path).writeAsString(contents);
}
