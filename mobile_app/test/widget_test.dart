import 'package:flutter_test/flutter_test.dart';
import 'package:camera_libre/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const CameraLibreApp());
    expect(find.byType(CameraLibreApp), findsOneWidget);
  });
}
