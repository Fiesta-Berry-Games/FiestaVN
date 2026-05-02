import 'renpy_dialogue_event.dart';
import 'renpy_presentation_snapshot.dart';

enum RenPyRunnerBlockPathBranch { block, ifEntry, menuChoice }

final class RenPyRunnerBlockPathSegment {
  const RenPyRunnerBlockPathSegment({
    required this.statementIndex,
    required this.branch,
    this.childIndex,
  });

  final int statementIndex;
  final RenPyRunnerBlockPathBranch branch;
  final int? childIndex;

  Map<String, Object?> toJson() => {
    'statementIndex': statementIndex,
    'branch': branch.name,
    if (childIndex != null) 'childIndex': childIndex,
  };

  factory RenPyRunnerBlockPathSegment.fromJson(Map<String, Object?> json) {
    return RenPyRunnerBlockPathSegment(
      statementIndex: json['statementIndex']! as int,
      branch: RenPyRunnerBlockPathBranch.values.firstWhere(
        (branch) => branch.name == json['branch'],
        orElse:
            () =>
                throw ArgumentError.value(
                  json['branch'],
                  'json[branch]',
                  'Unknown runner block path branch.',
                ),
      ),
      childIndex: json['childIndex'] as int?,
    );
  }
}

final class RenPyRunnerSnapshotStackFrame {
  const RenPyRunnerSnapshotStackFrame({
    required this.blockPath,
    required this.position,
    required this.kind,
    this.callerLabel,
  });

  final List<RenPyRunnerBlockPathSegment> blockPath;
  final int position;
  final String kind;

  /// The label that was current when a call frame was pushed, restored on
  /// return. Only meaningful for call frames.
  final String? callerLabel;

  Map<String, Object?> toJson() => {
    'blockPath': blockPath.map((segment) => segment.toJson()).toList(),
    'position': position,
    'kind': kind,
    if (callerLabel != null) 'callerLabel': callerLabel,
  };

  factory RenPyRunnerSnapshotStackFrame.fromJson(Map<String, Object?> json) {
    return RenPyRunnerSnapshotStackFrame(
      blockPath: _blockPathFromJson(json['blockPath']),
      position: json['position']! as int,
      kind: json['kind']! as String,
      callerLabel: json['callerLabel'] as String?,
    );
  }
}

final class RenPyRunnerSnapshotDialogue {
  const RenPyRunnerSnapshotDialogue({
    this.characterId,
    this.displayName,
    required this.text,
    this.color,
    this.autoContinueDuration,
  });

  factory RenPyRunnerSnapshotDialogue.fromEvent(RenPyDialogueEvent event) {
    return RenPyRunnerSnapshotDialogue(
      characterId: event.characterId,
      displayName: event.displayName,
      text: event.text,
      color: event.color,
      autoContinueDuration: event.autoContinueDuration,
    );
  }

  final String? characterId;
  final String? displayName;
  final String text;
  final String? color;
  final double? autoContinueDuration;

  RenPyDialogueEvent toDialogueEvent() {
    return RenPyDialogueEvent(
      characterId: characterId,
      displayName: displayName,
      text: text,
      color: color,
      autoContinueDuration: autoContinueDuration,
    );
  }

  Map<String, Object?> toJson() => {
    if (characterId != null) 'characterId': characterId,
    if (displayName != null) 'displayName': displayName,
    'text': text,
    if (color != null) 'color': color,
    if (autoContinueDuration != null)
      'autoContinueDuration': autoContinueDuration,
  };

  factory RenPyRunnerSnapshotDialogue.fromJson(Map<String, Object?> json) {
    return RenPyRunnerSnapshotDialogue(
      characterId: json['characterId'] as String?,
      displayName: json['displayName'] as String?,
      text: json['text']! as String,
      color: json['color'] as String?,
      autoContinueDuration: (json['autoContinueDuration'] as num?)?.toDouble(),
    );
  }
}

final class RenPyRunnerSnapshotPendingDialogue {
  const RenPyRunnerSnapshotPendingDialogue({
    required this.event,
    required this.searchStart,
  });

  final RenPyRunnerSnapshotDialogue event;
  final int searchStart;

  Map<String, Object?> toJson() => {
    'event': event.toJson(),
    'searchStart': searchStart,
  };

  factory RenPyRunnerSnapshotPendingDialogue.fromJson(
    Map<String, Object?> json,
  ) {
    return RenPyRunnerSnapshotPendingDialogue(
      event: RenPyRunnerSnapshotDialogue.fromJson(_mapFromJson(json['event'])),
      searchStart: json['searchStart']! as int,
    );
  }
}

final class RenPyRunnerSnapshot {
  const RenPyRunnerSnapshot({
    required this.state,
    required this.currentLabel,
    required this.currentBlockPath,
    required this.position,
    required this.stack,
    required this.variables,
    required this.persistent,
    required this.characters,
    this.lastDialogue,
    this.pendingDialogue,
    this.errorMessage,
    this.presentation,
  });

  final String state;
  final String? currentLabel;
  final List<RenPyRunnerBlockPathSegment> currentBlockPath;
  final int position;
  final List<RenPyRunnerSnapshotStackFrame> stack;
  final Map<String, dynamic> variables;
  final Map<String, dynamic> persistent;
  final Map<String, Map<String, dynamic>> characters;
  final RenPyRunnerSnapshotDialogue? lastDialogue;
  final RenPyRunnerSnapshotPendingDialogue? pendingDialogue;
  final String? errorMessage;
  final RenPyPresentationSnapshot? presentation;

  RenPyRunnerSnapshot withPresentation(RenPyPresentationSnapshot presentation) {
    return RenPyRunnerSnapshot(
      state: state,
      currentLabel: currentLabel,
      currentBlockPath: currentBlockPath,
      position: position,
      stack: stack,
      variables: variables,
      persistent: persistent,
      characters: characters,
      lastDialogue: lastDialogue,
      pendingDialogue: pendingDialogue,
      errorMessage: errorMessage,
      presentation: presentation,
    );
  }

  Map<String, Object?> toJson() => {
    'state': state,
    if (currentLabel != null) 'currentLabel': currentLabel,
    'currentBlockPath':
        currentBlockPath.map((segment) => segment.toJson()).toList(),
    'position': position,
    'stack': stack.map((frame) => frame.toJson()).toList(),
    'variables': variables,
    'persistent': persistent,
    'characters': characters,
    if (lastDialogue != null) 'lastDialogue': lastDialogue!.toJson(),
    if (pendingDialogue != null) 'pendingDialogue': pendingDialogue!.toJson(),
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (presentation != null) 'presentation': presentation!.toJson(),
  };

  factory RenPyRunnerSnapshot.fromJson(Map<String, Object?> json) {
    return RenPyRunnerSnapshot(
      state: json['state']! as String,
      currentLabel: json['currentLabel'] as String?,
      currentBlockPath: _blockPathFromJson(json['currentBlockPath']),
      position: json['position']! as int,
      stack:
          _listFromJson(json['stack'])
              .map(
                (item) =>
                    RenPyRunnerSnapshotStackFrame.fromJson(_mapFromJson(item)),
              )
              .toList(),
      variables: Map<String, dynamic>.from(_mapFromJson(json['variables'])),
      persistent: Map<String, dynamic>.from(_mapFromJson(json['persistent'])),
      characters: _charactersFromJson(json['characters']),
      lastDialogue:
          json['lastDialogue'] == null
              ? null
              : RenPyRunnerSnapshotDialogue.fromJson(
                _mapFromJson(json['lastDialogue']),
              ),
      pendingDialogue:
          json['pendingDialogue'] == null
              ? null
              : RenPyRunnerSnapshotPendingDialogue.fromJson(
                _mapFromJson(json['pendingDialogue']),
              ),
      errorMessage: json['errorMessage'] as String?,
      presentation:
          json['presentation'] == null
              ? null
              : RenPyPresentationSnapshot.fromJson(
                _mapFromJson(json['presentation']),
              ),
    );
  }
}

List<RenPyRunnerBlockPathSegment> _blockPathFromJson(Object? value) {
  return _listFromJson(value)
      .map((item) => RenPyRunnerBlockPathSegment.fromJson(_mapFromJson(item)))
      .toList();
}

Map<String, Map<String, dynamic>> _charactersFromJson(Object? value) {
  return _mapFromJson(value).map(
    (name, values) =>
        MapEntry(name, Map<String, dynamic>.from(_mapFromJson(values))),
  );
}

List<Object?> _listFromJson(Object? value) =>
    List<Object?>.from(value! as List);

Map<String, Object?> _mapFromJson(Object? value) {
  return Map<String, Object?>.from(value! as Map);
}

abstract interface class RenPyRunnerSnapshotStore {
  Future<RenPyRunnerSnapshot?> load();

  Future<void> save(RenPyRunnerSnapshot snapshot);

  Future<void> clear();
}

final class RenPyMemoryRunnerSnapshotStore implements RenPyRunnerSnapshotStore {
  RenPyRunnerSnapshot? _snapshot;

  @override
  Future<RenPyRunnerSnapshot?> load() async {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    return RenPyRunnerSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> save(RenPyRunnerSnapshot snapshot) async {
    _snapshot = RenPyRunnerSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> clear() async {
    _snapshot = null;
  }
}
