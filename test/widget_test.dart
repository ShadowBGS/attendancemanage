// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:attendance/main.dart';

void main() {
  testWidgets('Role selection renders and toggles role',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SmartAttendanceApp());
    await tester.pumpAndSettle();

    // Home screen should be the role selection page.
    expect(find.text('Select Your Role'), findsOneWidget);

    // Default role is lecturer.
    expect(find.text('Continue as Lecturer'), findsOneWidget);
    expect(find.text('Continue as Student'), findsNothing);

    // Switch to student.
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();

    expect(find.text('Continue as Student'), findsOneWidget);
  });
}
