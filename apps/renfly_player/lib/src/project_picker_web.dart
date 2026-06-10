import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_writer/renpy_writer.dart';
import 'package:web/web.dart' as web;

import 'project_picker_base.dart';

RenPyProjectPicker createPlatformRenPyProjectPicker() {
  return const BrowserRenPyProjectPicker();
}

final class BrowserRenPyProjectPicker implements RenPyProjectPicker {
  const BrowserRenPyProjectPicker();

  @override
  Future<PickedProject?> pickProject() async {
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

    return PickedProject(RenPyGameProject.fromFiles(files));
  }

  @override
  Future<PickedProject?> pickFile() async {
    final input =
        web.HTMLInputElement()
          ..type = 'file'
          ..accept = '.fly,.zip,.rpy';
    input.click();

    await input.onChange.first;
    final selectedFiles = input.files;
    if (selectedFiles == null || selectedFiles.length == 0) return null;

    final file = selectedFiles.item(0);
    if (file == null) return null;

    final bytes = await _readFile(file);
    final name = file.name.toLowerCase();

    if (name.endsWith('.fly.zip') || name.endsWith('.zip')) {
      final archive = FlyArchive.decode(bytes);
      final rpyText = archive.scriptAsRpy();
      final projectFiles = <RenPyProjectFile>[
        RenPyProjectFile.text('game/script.rpy', rpyText),
        for (final entry in archive.files)
          if (!entry.path.endsWith('.fly') && !entry.path.endsWith('.rpy'))
            RenPyProjectFile(entry.path, entry.bytes),
      ];
      return PickedProject(RenPyGameProject.fromFiles(projectFiles));
    }

    final source = utf8.decode(bytes);
    if (name.endsWith('.fly')) {
      final script = const FlyCodec().decodeFromString(
        source,
        filename: file.name,
      );
      final rpyText = const RenPyEmitter().emitScript(script);
      return PickedProject(
        RenPyGameProject.fromFiles([
          RenPyProjectFile.text('game/script.rpy', rpyText),
        ]),
      );
    }

    // .rpy — wrap as a single-file project.
    return PickedProject(
      RenPyGameProject.fromFiles([
        RenPyProjectFile.text('game/script.rpy', source),
      ]),
    );
  }

  @override
  Future<RenPyGameProject?> reloadProject(String sourcePath) async => null;

  Future<Uint8List> _readFile(web.File file) async {
    final buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}

bool _isRenPyProjectFile(String filePath) {
  final normalized = filePath.replaceAll(r'\', '/');
  return normalized.contains('/game/') || normalized.startsWith('game/');
}
