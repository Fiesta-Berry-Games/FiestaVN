import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import '../controller.dart';

/// Displays dialogue lines coming from [RenPyFlutterController].
class DialogueView extends StatelessWidget {
  const DialogueView({super.key, required this.controller});
  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is RenPyDialogue) {
          final who = status.character;
          return GestureDetector(
            onTap: controller.continueGame,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black.withValues(alpha: 0.6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (who != null)
                    Text(
                      who,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  const SizedBox(height: 4),
                  RenPyText(
                    status.text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }
        if (status is RenPyError) {
          return Center(child: Text('Error: ${status.message}'));
        }
        // Anything else -> render nothing (background stays visible).
        return const SizedBox.shrink();
      },
    );
  }
}
