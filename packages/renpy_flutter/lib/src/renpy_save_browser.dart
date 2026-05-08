import 'package:flutter/material.dart';
import 'package:renpy_core/renpy_core.dart';

import 'renpy_flutter_controller.dart';

/// How a save slot browser is being used.
enum RenPySaveBrowserMode { save, load }

/// A minimal multi-slot save/load browser backed by the controller's slot
/// store. Lists the quicksave and a fixed number of manual slots, lets the
/// player save into a slot (with overwrite confirmation), load a populated
/// slot, and delete a populated slot.
class RenPySaveBrowser extends StatefulWidget {
  const RenPySaveBrowser({
    super.key,
    required this.controller,
    required this.mode,
    required this.onClose,
    this.manualSlotCount = defaultManualSlotCount,
  });

  final RenPyFlutterController controller;
  final RenPySaveBrowserMode mode;
  final VoidCallback onClose;
  final int manualSlotCount;

  /// The slot identifier used for the single quicksave entry.
  static const quickSlot = 'quick';

  /// The number of numbered manual slots shown alongside the quicksave.
  static const defaultManualSlotCount = 6;

  @override
  State<RenPySaveBrowser> createState() => _RenPySaveBrowserState();
}

class _RenPySaveBrowserState extends State<RenPySaveBrowser> {
  Map<String, RenPyRunnerSlotMetadata>? _slots;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final metadata = await widget.controller.listSaveSlots();
    if (!mounted) return;
    setState(() {
      _slots = {for (final entry in metadata) entry.slot: entry};
    });
  }

  List<String> get _slotIds => [
    RenPySaveBrowser.quickSlot,
    for (var index = 1; index <= widget.manualSlotCount; index += 1) '$index',
  ];

  String _slotTitle(String slot) {
    if (slot == RenPySaveBrowser.quickSlot) return 'Quicksave';
    return 'Slot $slot';
  }

  Future<void> _save(String slot, {required bool occupied}) async {
    if (occupied) {
      final confirmed = await _confirmOverwrite(slot);
      if (!confirmed || !mounted) return;
    }
    final saved = await widget.controller.saveToSlot(slot);
    if (!mounted) return;
    if (saved) {
      await _refresh();
    } else {
      _showMessage('Nothing to save.');
    }
  }

  Future<void> _load(String slot) async {
    final loaded = await widget.controller.loadFromSlot(slot);
    if (!mounted) return;
    if (loaded) {
      widget.onClose();
    } else {
      _showMessage('Could not load slot.');
    }
  }

  Future<void> _delete(String slot) async {
    await widget.controller.deleteSlot(slot);
    if (!mounted) return;
    await _refresh();
  }

  Future<bool> _confirmOverwrite(String slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Overwrite save?'),
          content: Text('${_slotTitle(slot)} already has a save.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Overwrite'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isSave = widget.mode == RenPySaveBrowserMode.save;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isSave ? 'Save' : 'Load',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Flexible(child: _buildSlotList()),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.onClose,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildSlotList() {
    final slots = _slots;
    if (slots == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final slot in _slotIds) _buildSlotTile(slot, slots[slot]),
      ],
    );
  }

  Widget _buildSlotTile(String slot, RenPyRunnerSlotMetadata? metadata) {
    final isSave = widget.mode == RenPySaveBrowserMode.save;
    final occupied = metadata != null;
    final subtitle = occupied ? _slotSubtitle(metadata) : 'Empty';
    final enabled = isSave || occupied;

    return ListTile(
      key: ValueKey('renpy-save-slot-$slot'),
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(occupied ? Icons.save : Icons.add),
      title: Text(_slotTitle(slot)),
      subtitle: Text(subtitle),
      trailing:
          occupied
              ? IconButton(
                key: ValueKey('renpy-save-slot-delete-$slot'),
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(slot),
              )
              : null,
      onTap:
          !enabled
              ? null
              : () {
                if (isSave) {
                  _save(slot, occupied: occupied);
                } else {
                  _load(slot);
                }
              },
    );
  }

  String _slotSubtitle(RenPyRunnerSlotMetadata metadata) {
    final preview = metadata.preview ?? metadata.label;
    final when = _formatTimestamp(metadata.savedAt.toLocal());
    return preview == null ? when : '$when - $preview';
  }

  String _formatTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
