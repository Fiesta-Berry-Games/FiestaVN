// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:renpy_flutter/renpy_flutter.dart';

import 'project_picker_base.dart';

RenPyProjectPicker createPlatformRenPyProjectPicker() {
  return const BrowserRenPyProjectPicker();
}

final class BrowserRenPyProjectPicker implements RenPyProjectPicker {
  const BrowserRenPyProjectPicker();

  @override
  Future<RenPyGameProject?> pickProject() async {
    final input =
        html.FileUploadInputElement()
          ..multiple = true
          ..setAttribute('webkitdirectory', '')
          ..setAttribute('directory', '');
    input.click();

    await input.onChange.first;
    final selectedFiles = input.files;
    if (selectedFiles == null || selectedFiles.isEmpty) return null;

    final files = <RenPyProjectFile>[];
    for (final file in selectedFiles) {
      final relativePath = file.relativePath ?? file.name;
      if (!_isRenPyProjectFile(relativePath)) continue;
      final bytes = await _readFile(file);
      files.add(RenPyProjectFile(relativePath, bytes));
    }

    return RenPyGameProject.fromFiles(files);
  }

  Future<Uint8List> _readFile(html.File file) async {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);

    await Future.any([
      reader.onLoad.first,
      reader.onError.first.then((_) {
        throw StateError('Failed to read ${file.name}');
      }),
    ]);

    final result = reader.result;
    if (result is ByteBuffer) return Uint8List.view(result);
    if (result is Uint8List) return result;
    throw StateError('Failed to read ${file.name}');
  }
}

bool _isRenPyProjectFile(String filePath) {
  final normalized = filePath.replaceAll(r'\', '/');
  return normalized.contains('/game/') || normalized.startsWith('game/');
}
