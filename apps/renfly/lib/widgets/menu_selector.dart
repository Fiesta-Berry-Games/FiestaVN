import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

/// Overlay that shows Ren'Py in-game menus.
///
/// When the player taps a choice we forward the index back to the controller.
class MenuSelector extends StatelessWidget {
  const MenuSelector({super.key, required this.controller});
  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is! RenPyMenu) return const SizedBox.shrink();

        return Material(
          color: Colors.black54,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status.caption != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      status.caption!,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < status.choices.length; ++i)
                      ElevatedButton(
                        key: ValueKey('menu_choice_$i'),
                        onPressed: () => status.onChoice(i),
                        child: Text(status.choices[i]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
