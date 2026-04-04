import 'renpy_image_placement.dart';
import 'renpy_resolved_image.dart';

final class RenPyPresentationSnapshot {
  const RenPyPresentationSnapshot({this.visual, this.audio});

  final RenPyVisualSnapshot? visual;
  final RenPyAudioSnapshot? audio;

  Map<String, Object?> toJson() => {
    if (visual != null) 'visual': visual!.toJson(),
    if (audio != null) 'audio': audio!.toJson(),
  };

  factory RenPyPresentationSnapshot.fromJson(Map<String, Object?> json) {
    return RenPyPresentationSnapshot(
      visual:
          json['visual'] == null
              ? null
              : RenPyVisualSnapshot.fromJson(_mapFromJson(json['visual'])),
      audio:
          json['audio'] == null
              ? null
              : RenPyAudioSnapshot.fromJson(_mapFromJson(json['audio'])),
    );
  }
}

final class RenPyVisualSnapshot {
  const RenPyVisualSnapshot({this.scene, this.sprites = const []});

  final RenPyVisualElementSnapshot? scene;
  final List<RenPyVisualElementSnapshot> sprites;

  Map<String, Object?> toJson() => {
    if (scene != null) 'scene': scene!.toJson(),
    'sprites': sprites.map((sprite) => sprite.toJson()).toList(),
  };

  factory RenPyVisualSnapshot.fromJson(Map<String, Object?> json) {
    return RenPyVisualSnapshot(
      scene:
          json['scene'] == null
              ? null
              : RenPyVisualElementSnapshot.fromJson(
                _mapFromJson(json['scene']),
              ),
      sprites:
          _listFromJson(json['sprites'])
              .map(
                (item) =>
                    RenPyVisualElementSnapshot.fromJson(_mapFromJson(item)),
              )
              .toList(),
    );
  }
}

final class RenPyVisualElementSnapshot {
  const RenPyVisualElementSnapshot({
    this.tag,
    this.imageName,
    this.assetPath,
    this.solidColor,
    this.operations = const [],
    this.placement,
    this.text,
  });

  final String? tag;
  final String? imageName;
  final String? assetPath;
  final RenPyColorValue? solidColor;
  final List<RenPyImageOperation> operations;
  final RenPyImagePlacement? placement;
  final String? text;

  Map<String, Object?> toJson() => {
    if (tag != null) 'tag': tag,
    if (imageName != null) 'imageName': imageName,
    if (assetPath != null) 'assetPath': assetPath,
    if (solidColor != null) 'solidColor': _colorToJson(solidColor!),
    if (operations.isNotEmpty)
      'operations': operations.map(_operationToJson).toList(),
    if (placement != null) 'placement': _placementToJson(placement!),
    if (text != null) 'text': text,
  };

  factory RenPyVisualElementSnapshot.fromJson(Map<String, Object?> json) {
    return RenPyVisualElementSnapshot(
      tag: json['tag'] as String?,
      imageName: json['imageName'] as String?,
      assetPath: json['assetPath'] as String?,
      solidColor:
          json['solidColor'] == null
              ? null
              : _colorFromJson(_mapFromJson(json['solidColor'])),
      operations:
          (json['operations'] == null
                  ? const <Object?>[]
                  : _listFromJson(json['operations']))
              .map((item) => _operationFromJson(_mapFromJson(item)))
              .toList(),
      placement:
          json['placement'] == null
              ? null
              : _placementFromJson(_mapFromJson(json['placement'])),
      text: json['text'] as String?,
    );
  }
}

final class RenPyAudioSnapshot {
  const RenPyAudioSnapshot({this.channels = const {}});

  final Map<String, RenPyAudioChannelSnapshot> channels;

  Map<String, Object?> toJson() => {
    'channels': channels.map(
      (name, channel) => MapEntry(name, channel.toJson()),
    ),
  };

  factory RenPyAudioSnapshot.fromJson(Map<String, Object?> json) {
    return RenPyAudioSnapshot(
      channels: _mapFromJson(json['channels']).map(
        (name, value) => MapEntry(
          name,
          RenPyAudioChannelSnapshot.fromJson(_mapFromJson(value)),
        ),
      ),
    );
  }
}

final class RenPyAudioChannelSnapshot {
  const RenPyAudioChannelSnapshot({required this.asset, this.mixer, this.loop});

  final String asset;
  final String? mixer;
  final bool? loop;

  Map<String, Object?> toJson() => {
    'asset': asset,
    if (mixer != null) 'mixer': mixer,
    if (loop != null) 'loop': loop,
  };

  factory RenPyAudioChannelSnapshot.fromJson(Map<String, Object?> json) {
    return RenPyAudioChannelSnapshot(
      asset: json['asset']! as String,
      mixer: json['mixer'] as String?,
      loop: json['loop'] as bool?,
    );
  }
}

Map<String, Object?> _placementToJson(RenPyImagePlacement placement) => {
  if (placement.xpos != null) 'xpos': placement.xpos,
  if (placement.ypos != null) 'ypos': placement.ypos,
  if (placement.xanchor != null) 'xanchor': placement.xanchor,
  if (placement.yanchor != null) 'yanchor': placement.yanchor,
  if (placement.xalign != null) 'xalign': placement.xalign,
  if (placement.yalign != null) 'yalign': placement.yalign,
  if (placement.expression != null) 'expression': placement.expression,
};

RenPyImagePlacement _placementFromJson(Map<String, Object?> json) {
  final expression = json['expression'] as String?;
  if (expression != null) return RenPyImagePlacement.unsupported(expression);
  return RenPyImagePlacement.position(
    xpos: (json['xpos'] as num?)?.toDouble(),
    ypos: (json['ypos'] as num?)?.toDouble(),
    xanchor: (json['xanchor'] as num?)?.toDouble(),
    yanchor: (json['yanchor'] as num?)?.toDouble(),
    xalign: (json['xalign'] as num?)?.toDouble(),
    yalign: (json['yalign'] as num?)?.toDouble(),
  );
}

Map<String, Object?> _colorToJson(RenPyColorValue color) => {
  'red': color.red,
  'green': color.green,
  'blue': color.blue,
  'alpha': color.alpha,
};

RenPyColorValue _colorFromJson(Map<String, Object?> json) {
  return RenPyColorValue(
    json['red']! as int,
    json['green']! as int,
    json['blue']! as int,
    json['alpha']! as int,
  );
}

Map<String, Object?> _operationToJson(RenPyImageOperation operation) => {
  'type': operation.type.name,
  if (operation.tintRed != null) 'tintRed': operation.tintRed,
  if (operation.tintGreen != null) 'tintGreen': operation.tintGreen,
  if (operation.tintBlue != null) 'tintBlue': operation.tintBlue,
};

RenPyImageOperation _operationFromJson(Map<String, Object?> json) {
  final type = RenPyImageOperationType.values.firstWhere(
    (candidate) => candidate.name == json['type'],
    orElse: () => throw ArgumentError.value(json['type'], 'json[type]'),
  );
  return switch (type) {
    RenPyImageOperationType.grayscale => const RenPyImageOperation.grayscale(),
    RenPyImageOperationType.sepia => const RenPyImageOperation.sepia(),
    RenPyImageOperationType.flipHorizontal =>
      const RenPyImageOperation.flipHorizontal(),
    RenPyImageOperationType.matrixColor => RenPyImageOperation.matrixColor(
      tintRed: (json['tintRed']! as num).toDouble(),
      tintGreen: (json['tintGreen']! as num).toDouble(),
      tintBlue: (json['tintBlue']! as num).toDouble(),
    ),
  };
}

List<Object?> _listFromJson(Object? value) =>
    List<Object?>.from(value! as List);

Map<String, Object?> _mapFromJson(Object? value) {
  return Map<String, Object?>.from(value! as Map);
}
