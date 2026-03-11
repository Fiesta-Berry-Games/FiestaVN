import 'project_picker_base.dart';

RenPyProjectPicker createPlatformRenPyProjectPicker() {
  return const UnsupportedRenPyProjectPicker(
    'Opening RenPy project folders is currently implemented for web builds.',
  );
}
