import 'package:renpy_flutter/renpy_flutter.dart';

/// A project chosen through the picker plus, where available, the durable
/// source path it was loaded from.
///
/// [sourcePath] is non-null when the platform can reload the project later
/// (desktop/mobile folder paths). Web uploads have no durable path, so it is
/// null there and the project must be re-picked on a future launch.
final class PickedProject {
  const PickedProject(this.project, {this.sourcePath});

  final RenPyGameProject project;
  final String? sourcePath;
}

abstract interface class RenPyProjectPicker {
  /// Prompts the user to choose a project folder/upload.
  Future<PickedProject?> pickProject();

  /// Reloads a previously chosen project from its durable [sourcePath].
  ///
  /// Returns null when the platform cannot reload from a path (e.g. web).
  Future<RenPyGameProject?> reloadProject(String sourcePath);
}

final class UnsupportedRenPyProjectPicker implements RenPyProjectPicker {
  const UnsupportedRenPyProjectPicker(this.message);

  final String message;

  @override
  Future<PickedProject?> pickProject() {
    throw UnsupportedError(message);
  }

  @override
  Future<RenPyGameProject?> reloadProject(String sourcePath) async => null;
}
