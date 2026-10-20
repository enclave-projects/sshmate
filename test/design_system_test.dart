// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshmate/ui/design_system.dart';
import 'package:sshmate/ui/theme.dart';

void main() {
  testWidgets(
    'Interactive surface supports keyboard activation and reduced motion',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: MateSurface(
                onTap: () => activations++,
                child: const Text('Connect'),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activations, 1);
    },
  );
  testWidgets('Error notice announces its message', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(light: true),
        home: const Scaffold(
          body: MateNotice('Connection failed', error: true),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Connection failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    handle.dispose();
  });
}
