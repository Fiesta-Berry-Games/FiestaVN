import 'package:flutter_test/flutter_test.dart';
import 'package:renspine/main.dart';

void main() {
  testWidgets('launcher lists Reference Game 1', (tester) async {
    await tester.pumpWidget(const FiestaVNApp());

    expect(find.text('Choose a demo game'), findsOneWidget);
    expect(find.text('Reference Game 1'), findsOneWidget);
  });
}
