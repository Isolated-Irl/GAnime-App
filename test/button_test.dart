// Verification test for the white-button fix (2026-10-29).
// The user's white accent made button text invisible (white-on-white).
// This test proves gaGreenButton picks dark text on light backgrounds.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganime/screens/settings/settings_shell.dart';

void main() {
  testWidgets('gaGreenButton uses dark text on white accent',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.white,
            brightness: Brightness.dark,
          ).copyWith(primary: Colors.white),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => gaGreenButton(
              context: context,
              label: 'Connect with AniList',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    // Find the button and check its text color is dark (readable on white).
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final style = button.style!;
    // Resolve the foreground color from the button style.
    final fg = style.foregroundColor!.resolve({});
    expect(fg, isNotNull, reason: 'Button must have a foreground color');
    // White text on white background is the bug — must be dark now.
    expect(fg, isNot(equals(Colors.white)),
        reason: 'Text must not be white on white accent');
    // Luminance check: dark text has low luminance.
    expect(fg!.computeLuminance() < 0.5, isTrue,
        reason: 'Text must be dark for readability on white');
  });

  testWidgets('gaGreenButton uses white text on dark accent',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.dark,
          ).copyWith(primary: Colors.green),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => gaGreenButton(
              context: context,
              label: 'Test',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final fg = button.style!.foregroundColor!.resolve({});
    expect(fg, equals(Colors.white),
        reason: 'Text should stay white on dark accent');
  });
}
