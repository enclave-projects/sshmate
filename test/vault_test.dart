// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshmate/data/vault_repository.dart';
import 'package:sshmate/domain/models.dart';
import 'package:sshmate/ui/workspace_controller.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sshmate-vault-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('password change authenticates first and preserves existing vault on failure', () async {
    final vault = VaultRepository(directory: directory);
    await vault.create('original master password');
    await vault.save(
      Workspace(
        snippets: const [Snippet(id: '1', label: 'Keep', command: 'uptime')],
      ),
    );
    final original = await vault.exportBytes();
    await expectLater(
      vault.changePassword('wrong password', 'replacement master password'),
      throwsA(isA<VaultException>()),
    );
    expect(await vault.exportBytes(), original);
    expect(vault.workspace.snippets.single.label, 'Keep');
    await expectLater(
      vault.changePassword('original master password', 'short'),
      throwsA(isA<VaultException>()),
    );
    expect(await vault.exportBytes(), original);
    await vault.changePassword(
      'original master password',
      'replacement master password',
    );
    expect(vault.workspace.snippets.single.label, 'Keep');
    vault.lock();
    await expectLater(
      vault.unlock('original master password'),
      throwsA(isA<VaultException>()),
    );
    await vault.unlock('replacement master password');
    expect(vault.workspace.snippets.single.command, 'uptime');
  });
  test('restores encrypted bytes into an empty installation', () async {
    final source = VaultRepository(
      directory: Directory('${directory.path}/source'),
    );
    await source.create('source master password');
    await source.save(
      Workspace(
        snippets: const [
          Snippet(id: '1', label: 'Restored', command: 'uptime'),
        ],
      ),
    );
    final export = File('${directory.path}/portable.sshmate');
    await export.writeAsBytes(await source.exportBytes());
    final restored = VaultRepository(
      directory: Directory('${directory.path}/restore'),
    );
    await restored.restoreFrom(export, 'source master password');
    expect(restored.workspace.snippets.single.label, 'Restored');
    restored.lock();
    await expectLater(
      restored.restoreFrom(export, 'source master password'),
      throwsA(isA<VaultException>()),
    );
    await restored.unlock('source master password');
    expect(restored.workspace.snippets.single.command, 'uptime');
  });
  test(
    'serializes concurrent changes and cancels queued changes on lock',
    () async {
      final vault = VaultRepository(directory: directory);
      final controller = WorkspaceController(repository: vault);
      await controller.create('a strong master password');
      await Future.wait([
        controller.upsertHost(Host(id: 'a', label: 'A', address: 'localhost')),
        controller.upsertHost(Host(id: 'b', label: 'B', address: 'localhost')),
        controller.trustHost('localhost:22', 'fingerprint'),
        controller.updateSettings({'fontSize': 14}),
        controller.recordHistory('connected to A'),
      ]);
      expect(controller.workspace.hosts, hasLength(2));
      expect(controller.workspace.knownHosts['localhost:22'], 'fingerprint');
      expect(controller.workspace.settings['fontSize'], 14);
      expect(controller.workspace.history.single, 'connected to A');
      final pending = controller.upsertHost(
        Host(id: 'c', label: 'C', address: 'localhost'),
      );
      final cancellation = expectLater(pending, throwsA(isA<VaultException>()));
      controller.lock();
      await cancellation;
      await controller.unlock('a strong master password');
      expect(controller.workspace.hosts, hasLength(2));
      controller.dispose();
    },
  );
  test(
    'persists encrypted secrets, rejects wrong passwords and locks access',
    () async {
      final vault = VaultRepository(directory: directory);
      await vault.create('a strong master password');
      await vault.save(
        Workspace(
          hosts: [
            Host(id: 'host', label: 'Private machine', address: '10.1.2.3'),
          ],
          identities: const [
            Identity(
              id: 'key',
              label: 'Secret',
              password: 'sensitive-password',
            ),
          ],
        ),
      );
      final envelope = await File('${directory.path}/workspace.sshmate')
          .readAsString();
      expect(envelope, isNot(contains('sensitive-password')));
      expect(envelope, isNot(contains('10.1.2.3')));
      vault.lock();
      expect(() => vault.workspace, throwsA(isA<VaultException>()));
      await expectLater(
        vault.unlock('wrong password'),
        throwsA(isA<VaultException>()),
      );
      expect(vault.isUnlocked, isFalse);
      final reopened = VaultRepository(directory: directory);
      await reopened.unlock('a strong master password');
      expect(reopened.workspace.hosts.single.address, '10.1.2.3');
      expect(
        reopened.workspace.identities.single.password,
        'sensitive-password',
      );
    },
  );
  test('rejects modified authenticated ciphertext', () async {
    final vault = VaultRepository(directory: directory);
    await vault.create('a strong master password');
    vault.lock();
    final file = File('${directory.path}/workspace.sshmate');
    final envelope =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final ciphertext = base64Decode(envelope['ciphertext']);
    ciphertext[0] ^= 1;
    envelope['ciphertext'] = base64Encode(ciphertext);
    await file.writeAsString(jsonEncode(envelope));
    await expectLater(
      vault.unlock('a strong master password'),
      throwsA(isA<VaultException>()),
    );
    expect(vault.isUnlocked, isFalse);
  });
  test('portable import encrypts data with destination password', () async {
    final source = VaultRepository(
      directory: Directory('${directory.path}/source'),
    );
    await source.create('source master password');
    await source.save(
      Workspace(
        snippets: const [Snippet(id: '1', label: 'Uptime', command: 'uptime')],
      ),
    );
    final export = File('${directory.path}/portable.sshmate');
    await source.exportTo(export);
    final destination = VaultRepository(
      directory: Directory('${directory.path}/destination'),
    );
    await destination.create('destination master password');
    await destination.importFrom(export, 'source master password');
    destination.lock();
    await destination.unlock('destination master password');
    expect(destination.workspace.snippets.single.command, 'uptime');
    destination.lock();
    await expectLater(
      destination.unlock('source master password'),
      throwsA(isA<VaultException>()),
    );
  });
}
