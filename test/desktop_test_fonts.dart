// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadDesktopFonts(WidgetTester tester) async {
  if (!Platform.isWindows) return;
  await tester.runAsync(() async {
    final font = FontLoader('Segoe UI');
    final bytes = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
    font.addFont(Future.value(ByteData.sublistView(bytes)));
    await font.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
}
