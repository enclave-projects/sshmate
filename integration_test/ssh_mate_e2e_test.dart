// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sshmate/data/ssh_service.dart';
import 'package:sshmate/data/vault_repository.dart';
import 'package:sshmate/domain/models.dart';
import 'package:sshmate/ui/app.dart';
import 'package:sshmate/ui/terminal_pane.dart';
import 'package:xterm/xterm.dart';

Future<void> waitUntil(
  WidgetTester tester,
  bool Function() ready, {
  String reason = 'UI condition',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  expect(ready(), isTrue, reason: reason);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows vault unlock, trusted SSH PTY, SFTP, disconnect and lock', (
    tester,
  ) async {
    const repositoryRoot = String.fromEnvironment('SSH_MATE_REPO');
    final root = repositoryRoot.isEmpty
        ? Directory.current.path
        : repositoryRoot;
    final fixture = await Process.start('python', [
      '$root/test/fixtures/ssh_loopback.py',
    ]);
    final fixtureErrors = StringBuffer();
    fixture.stderr.transform(utf8.decoder).listen(fixtureErrors.write);
    addTearDown(() async {
      fixture.kill();
      await fixture.exitCode;
    });
    final metadataLine = await fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw StateError(
            'Loopback fixture failed. Install Python paramiko. $fixtureErrors',
          ),
        );
    final metadata = jsonDecode(metadataLine) as Map<String, dynamic>;
    final host = Host(
      id: 'acceptance-host',
      label: 'Isolated acceptance server',
      address: '127.0.0.1',
      port: metadata['port'] as int,
      username: 'fixture',
      identityId: 'acceptance-identity',
    );
    const identity = Identity(
      id: 'acceptance-identity',
      label: 'Ephemeral fixture',
      username: 'fixture',
      password: 'test-only',
    );
    final directory = await Directory.systemTemp.createTemp(
      'ssh-mate-native-e2e-',
    );
    final repository = VaultRepository(directory: directory);
    addTearDown(() async {
      repository.lock();
      await directory.delete(recursive: true);
    });
    const password = 'isolated acceptance vault password';
    await repository.create(password);
    await repository.save(Workspace(hosts: [host], identities: [identity]));
    repository.lock();
    final seed = await SshService().connect(
      host: host,
      identity: identity,
      verifyHostKey: (_, _) async => true,
    );
    final local = File('${directory.path}/fixture-source.txt');
    await local.writeAsString('Native Windows acceptance transfer\n');
    await seed.upload(local.path, '/acceptance.txt');
    await seed.close();

    await tester.pumpWidget(SshMateApp(repository: repository));
    await waitUntil(
      tester,
      () => find.text('Welcome back').evaluate().isNotEmpty,
      reason: 'Existing isolated vault appears',
    );
    await tester.enterText(find.byKey(const Key('vault-password')), password);
    await tester.tap(find.byKey(const Key('vault-submit')));
    await waitUntil(
      tester,
      () => find.text(host.label).evaluate().isNotEmpty,
      reason: 'Password unlock exposes persisted host',
    );
    await tester.tap(find.text(host.label));
    await waitUntil(
      tester,
      () => find.text('Trust this host?').evaluate().isNotEmpty,
      reason: 'Unknown SSH key requires explicit trust',
    );
    expect(find.textContaining('SHA256:'), findsWidgets);
    await tester.tap(find.text('Trust and connect'));
    await waitUntil(
      tester,
      () => find.text('Connected · encrypted SSH').evaluate().isNotEmpty,
      reason: 'Authenticated native terminal connects',
    );
    expect(repository.workspace.knownHosts, isNotEmpty);
    // First allow the real Windows input client attachment, then use Flutter's
    // IME event simulator for deterministic text entry (not the SSH send API).
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final terminalFocus = tester
        .widget<TerminalView>(find.byType(TerminalView))
        .focusNode!;
    expect(terminalFocus.hasFocus, isTrue);
    terminalFocus.unfocus();
    await tester.pump();
    tester.testTextInput.register();
    terminalFocus.requestFocus();
    await tester.pump();
    final attach = tester.testTextInput.log.lastWhere(
      (call) => call.method == 'TextInput.setClient',
    );
    expect(((attach.arguments as List)[1] as Map)['viewId'], isNotNull);
    tester.testTextInput.enterText('native-windows-e2e-echo');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await waitUntil(
      tester,
      () => tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal
          .buffer
          .getText()
          .contains('native-windows-e2e-echo'),
      reason: 'Actual SSH roundtrip reaches xterm buffer',
    );
    await tester.tap(find.widgetWithText(TextButton, 'SFTP'));
    await waitUntil(
      tester,
      () => find.text('acceptance.txt').evaluate().isNotEmpty,
      reason: 'Real SFTP directory is rendered',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Terminal'));
    await tester.pumpAndSettle();
    expect(terminalFocus.hasFocus, isTrue);
    tester.testTextInput.enterText('after-sftp-switch');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await waitUntil(
      tester,
      () => tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal
          .buffer
          .getText()
          .contains('after-sftp-switch'),
      reason: 'Typing works after returning from SFTP',
    );
    tester.testTextInput.unregister();
      await tester.tap(find.widgetWithText(TextButton, 'Workspace'));
      await tester.pumpAndSettle();
      expect(terminalFocus.hasFocus, isFalse);
      await tester.tap(find.widgetWithText(TextButton, host.label));
      await tester.pumpAndSettle();
      expect(terminalFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close session'));
    await waitUntil(
      tester,
      () => find.byType(TerminalPane).evaluate().isEmpty,
      reason: 'Closing session disposes terminal and transport',
    );
    await tester.tap(find.text('Lock workspace'));
    await waitUntil(
      tester,
      () => find.text('Welcome back').evaluate().isNotEmpty,
      reason: 'Lock removes decrypted workspace',
    );
    expect(repository.isUnlocked, isFalse);
    expect(find.byType(TerminalPane), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
