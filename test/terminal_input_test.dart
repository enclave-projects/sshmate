// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets(
    'Terminal attaches to its view and routes text and control keys',
    (tester) async {
      final terminal = Terminal();
      final output = StringBuffer();
      terminal.onOutput = output.write;
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TerminalView(terminal, focusNode: focus)),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      final attach = tester.testTextInput.log.lastWhere(
        (call) => call.method == 'TextInput.setClient',
      );
      final configuration = (attach.arguments as List)[1] as Map;
      expect(configuration['viewId'], tester.view.viewId);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('uname -a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(output.toString(), 'uname -a\r');
      output.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(output.toString(), '\x03\x1b[A\x7f');
      focus.unfocus();
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
