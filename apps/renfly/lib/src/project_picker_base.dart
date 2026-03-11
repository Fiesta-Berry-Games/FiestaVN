import 'package:renpy_flutter/renpy_flutter.dart';

abstract interface class RenPyProjectPicker {
  Future<RenPyGameProject?> pickProject();
}

final class UnsupportedRenPyProjectPicker implements RenPyProjectPicker {
  const UnsupportedRenPyProjectPicker(this.message);

  final String message;

  @override
  Future<RenPyGameProject?> pickProject() {
    throw UnsupportedError(message);
  }
}
