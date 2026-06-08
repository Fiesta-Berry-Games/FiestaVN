import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'project_picker_base.dart';

RenPyProjectPicker createPlatformRenPyProjectPicker() {
  return const DesktopRenPyProjectPicker();
}

final class DesktopRenPyProjectPicker implements RenPyProjectPicker {
  const DesktopRenPyProjectPicker();

  @override
  Future<PickedProject?> pickProject() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Open RenPy project folder',
    );
    if (folder == null) return null;

    final project = await _loadFolder(folder);
    return PickedProject(project, sourcePath: folder);
  }

  @override
  Future<RenPyGameProject?> reloadProject(String sourcePath) async {
    if (!Directory(sourcePath).existsSync()) return null;
    return _loadFolder(sourcePath);
  }

  Future<RenPyGameProject> _loadFolder(String folder) async {
    final root = Directory(folder);
    final files = <RenPyProjectFile>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      if (!_isRenPyProjectFile(entity.path)) continue;
      files.add(RenPyProjectFile(entity.path, await entity.readAsBytes()));
    }

    return RenPyGameProject.fromFiles(files);
  }
}

bool _isRenPyProjectFile(String filePath) {
  final normalized = filePath.replaceAll(r'\', '/');
  return normalized.contains('/game/') || normalized.startsWith('game/');
}
