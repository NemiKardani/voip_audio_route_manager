import 'package:flutter_test/flutter_test.dart';
import 'package:voip_audio_route_manager_example/main.dart';

void main() {
  testWidgets('Verify Example App UI builds and shows initialization button',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify the App Bar title is present.
    expect(find.text('VoIP Audio Route Manager'), findsOneWidget);

    // Verify that the setup text is displayed.
    expect(find.text('Setup Platform Audio Routing'), findsOneWidget);

    // Verify that the 'Initialize Manager' button is present.
    expect(find.text('Initialize Manager'), findsOneWidget);
  });
}
