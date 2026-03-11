import 'src/project_picker_base.dart';
import 'src/project_picker_stub.dart'
    if (dart.library.html) 'src/project_picker_web.dart'
    if (dart.library.io) 'src/project_picker_io.dart'
    as platform;

export 'src/project_picker_base.dart';

RenPyProjectPicker createRenPyProjectPicker() {
  return platform.createPlatformRenPyProjectPicker();
}
