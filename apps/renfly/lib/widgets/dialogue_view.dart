import 'package:flutter/material.dart';
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
            behavior: HitTestBehavior.opaque,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 112),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (who != null) ...[
                        Text(
                          who,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        status.text,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (status is RenPyError) {
          return Center(child: Text('Error: ${status.message}'));
        }
        // Anything else → render nothing (background stays visible).
        return const SizedBox.shrink();
      },
    );
  }
}
