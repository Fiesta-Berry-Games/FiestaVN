import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:web/web.dart' as web;

import 'project_picker_base.dart';

RenPyProjectPicker createPlatformRenPyProjectPicker() {
  return const BrowserRenPyProjectPicker();
}

final class BrowserRenPyProjectPicker implements RenPyProjectPicker {
  const BrowserRenPyProjectPicker();

  @override
  Future<RenPyGameProject?> pickProject() async {
    final input =
        web.HTMLInputElement()
          ..type = 'file'
          ..multiple = true;
    input.setAttribute('webkitdirectory', '');
    input.setAttribute('directory', '');
    input.click();

    await input.onChange.first;
    final selectedFiles = input.files;
    if (selectedFiles == null || selectedFiles.length == 0) return null;

    final files = <RenPyProjectFile>[];
    for (var i = 0; i < selectedFiles.length; i += 1) {
      final file = selectedFiles.item(i);
      if (file == null) continue;
      final relativePath =
          file.webkitRelativePath.isNotEmpty
              ? file.webkitRelativePath
              : file.name;
      if (!_isRenPyProjectFile(relativePath)) continue;
      final bytes = await _readFile(file);
      files.add(RenPyProjectFile(relativePath, bytes));
    }

    return RenPyGameProject.fromFiles(files);
  }

  Future<Uint8List> _readFile(web.File file) async {
    final buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}

bool _isRenPyProjectFile(String filePath) {
  final normalized = filePath.replaceAll(r'\', '/');
  return normalized.contains('/game/') || normalized.startsWith('game/');
}
