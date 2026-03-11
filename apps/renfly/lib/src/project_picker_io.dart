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
  Future<RenPyGameProject?> pickProject() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Open RenPy project folder',
    );
    if (folder == null) return null;

    final root = Directory(folder);
    final files = <RenPyProjectFile>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      files.add(RenPyProjectFile(entity.path, await entity.readAsBytes()));
    }

    return RenPyGameProject.fromFiles(files);
  }
}
