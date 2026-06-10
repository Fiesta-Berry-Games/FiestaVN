import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_writer/renpy_writer.dart';

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
  Future<PickedProject?> pickFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open .fly or .fly.zip file',
      type: FileType.custom,
      allowedExtensions: const ['fly', 'zip', 'rpy'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    final project = _loadFileBytes(file.name, bytes);
    return PickedProject(project, sourcePath: file.path);
  }

  @override
  Future<RenPyGameProject?> reloadProject(String sourcePath) async {
    if (Directory(sourcePath).existsSync()) {
      return _loadFolder(sourcePath);
    }
    if (File(sourcePath).existsSync()) {
      final file = File(sourcePath);
      final bytes = await file.readAsBytes();
      return _loadFileBytes(sourcePath.split('/').last, bytes);
    }
    return null;
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

RenPyGameProject _loadFileBytes(String filename, List<int> bytes) {
  final name = filename.toLowerCase();
  if (name.endsWith('.fly.zip') || name.endsWith('.zip')) {
    return _loadFlyZip(bytes);
  }
  final source = utf8.decode(bytes);
  if (name.endsWith('.fly')) {
    return _loadFlyScript(source, filename);
  }
  // .rpy — wrap as a single-file project.
  return RenPyGameProject.fromFiles([
    RenPyProjectFile.text('game/script.rpy', source),
  ]);
}

RenPyGameProject _loadFlyScript(String source, String filename) {
  final script = const FlyCodec().decodeFromString(source, filename: filename);
  final rpyText = const RenPyEmitter().emitScript(script);
  return RenPyGameProject.fromFiles([
    RenPyProjectFile.text('game/script.rpy', rpyText),
  ]);
}

RenPyGameProject _loadFlyZip(List<int> zipBytes) {
  final archive = FlyArchive.decode(
    zipBytes is Uint8List ? zipBytes : Uint8List.fromList(zipBytes),
  );
  final rpyText = archive.scriptAsRpy();
  final files = <RenPyProjectFile>[
    RenPyProjectFile.text('game/script.rpy', rpyText),
    for (final entry in archive.files)
      if (!entry.path.endsWith('.fly') && !entry.path.endsWith('.rpy'))
        RenPyProjectFile(entry.path, entry.bytes),
  ];
  return RenPyGameProject.fromFiles(files);
}

bool _isRenPyProjectFile(String filePath) {
  final normalized = filePath.replaceAll(r'\', '/');
  return normalized.contains('/game/') || normalized.startsWith('game/');
}
