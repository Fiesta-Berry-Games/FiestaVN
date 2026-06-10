import 'project_picker_base.dart';

RenPyProjectPicker createPlatformRenPyProjectPicker() {
  return const UnsupportedRenPyProjectPicker(
    'Opening RenPy project folders is not available on this platform.',
  );
}
