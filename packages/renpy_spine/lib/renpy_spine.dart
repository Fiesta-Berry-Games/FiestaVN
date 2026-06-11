/// Spine character displayables for the FiestaVN Ren'Py engine: show
/// Spine-animated sprites from Ren'Py scripts.
library;

// Hosts must call initSpineFlutter() before showing any Spine sprite;
// re-exported so apps need no direct spine_flutter dependency.
export 'package:spine_flutter/spine_flutter.dart' show initSpineFlutter;

export 'src/spine_character.dart';
export 'src/spine_image_layer.dart';
export 'src/spine_image_name.dart';
export 'src/spine_sprite_widget.dart';
