// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'desktop_test_fonts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshmate/data/vault_repository.dart';
import 'package:sshmate/ui/app.dart';

Future<void> waitForUi(WidgetTester tester, bool Function() ready) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 1200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pumpAndSettle();
  expect(ready(), isTrue);
}

void main() {
  testWidgets('Create, lock, reject wrong password, and unlock local vault', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await loadDesktopFonts(tester);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('sshmate-gate-'),
    ))!;
    final repository = (await tester.runAsync(
      () async => VaultRepository(directory: directory),
    ))!;
    addTearDown(() async {
      repository.lock();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(SshMateApp(repository: repository));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Create your local vault'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('vault-password')), 'short');
    await tester.enterText(find.byKey(const Key('vault-confirm')), 'short');
    await tester.tap(find.byKey(const Key('vault-submit')));
    await tester.pump();
    expect(
      find.text('Use at least 12 characters and matching passwords.'),
      findsOneWidget,
    );
    expect(repository.isUnlocked, isFalse);
    const password = 'local test vault password';
    await tester.enterText(find.byKey(const Key('vault-password')), password);
    await tester.enterText(find.byKey(const Key('vault-confirm')), password);
    await tester.runAsync(() async {
      final dynamic submit = tester
          .widget<FilledButton>(find.byKey(const Key('vault-submit')))
          .onPressed;
      await submit();
    });
    await waitForUi(tester, () => repository.isUnlocked);
    expect(find.text('Your next connection starts here'), findsOneWidget);
    await tester.tap(find.text('Lock workspace'));
    await tester.pumpAndSettle();
    expect(repository.isUnlocked, isFalse);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('vault-password')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const Key('vault-password')),
      'incorrect password',
    );
    await tester.runAsync(() async {
      final dynamic submit = tester
          .widget<FilledButton>(find.byKey(const Key('vault-submit')))
          .onPressed;
      await submit();
    });
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open vault. Check your password and vault file.'),
      findsOneWidget,
    );
    expect(repository.isUnlocked, isFalse);
    await tester.enterText(find.byKey(const Key('vault-password')), password);
    await tester.runAsync(() async {
      final dynamic submit = tester
          .widget<FilledButton>(find.byKey(const Key('vault-submit')))
          .onPressed;
      await submit();
    });
    await waitForUi(tester, () => repository.isUnlocked);
    expect(find.text('Your next connection starts here'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
