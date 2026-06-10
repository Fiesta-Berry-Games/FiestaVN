import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'project_picker.dart';

void main() => runApp(const RenPyFlutterExampleApp());

/// A deliberately small example for the `renpy_flutter` package.
///
/// It does two things:
///  * plays a tiny bundled Ren'Py script so the package renders something with
///    no setup, and
///  * lets you open a real Ren'Py game folder ("from the wild") to exercise the
///    engine against actual content.
///
/// It is intentionally unopinionated - for a fuller, styled player see the
/// RenFly app in `apps/renfly_player`.
class RenPyFlutterExampleApp extends StatelessWidget {
  const RenPyFlutterExampleApp({super.key, this.projectPicker});

  /// Overridable for tests; defaults to the platform picker.
  final RenPyProjectPicker? projectPicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'renpy_flutter example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: HomeScreen(
        projectPicker: projectPicker ?? createRenPyProjectPicker(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.projectPicker});

  final RenPyProjectPicker projectPicker;

  void _playBundledSample(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Bundled sample')),
          body: const RenPyAssetPlayer(
            scriptAsset: 'assets/game/script.rpy',
            backgroundColor: Colors.black,
          ),
        ),
      ),
    );
  }

  Future<void> _openGameFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final picked = await projectPicker.pickProject();
      if (picked == null) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(picked.project.name)),
            body: RenPyProjectPlayer(
              project: picked.project,
              backgroundColor: Colors.black,
            ),
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open that folder: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('renpy_flutter example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => _playBundledSample(context),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play bundled sample'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _openGameFolder(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('Open game folder...'),
            ),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Open a folder containing a Ren\'Py "game/" directory '
                '(loose .rpy files or an .rpa archive) to play a real game.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
