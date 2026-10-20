// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/vault_repository.dart';
import '../domain/models.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.repository});
  final VaultRepository repository;
  Future<void> _mutations = Future.value();
  int _generation = 0;
  bool get isUnlocked => repository.isUnlocked;
  Workspace get workspace => repository.workspace;
  String query = '';
  String? selectedGroup;
  List<Host> get filteredHosts => workspace.hosts
      .where(
        (h) =>
            (selectedGroup == null || h.group == selectedGroup) &&
            '${h.label} ${h.address} ${h.username} ${h.tags.join(' ')}'
                .toLowerCase()
                .contains(query.toLowerCase()),
      )
      .toList();
  Future<bool> exists() => repository.exists();
  Future<void> create(String password) async {
    _generation++;
    await repository.create(password);
    notifyListeners();
  }

  Future<void> unlock(String password) async {
    _generation++;
    await repository.unlock(password);
    notifyListeners();
  }

  void lock() {
    _generation++;
    repository.lock();
    query = '';
    selectedGroup = null;
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final generation = _generation;
    final operation = _mutations.then((_) async {
      if (generation != _generation) {
        throw const VaultException('Vault operation cancelled.');
      }
      await action();
      if (generation == _generation) notifyListeners();
    });
    _mutations = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> save(Workspace value) => _enqueue(() => repository.save(value));

  Future<void> _mutate(Workspace Function(Workspace) update) =>
      _enqueue(() => repository.save(update(workspace)));

  void filter({String? text, String? group}) {
    query = text ?? query;
    selectedGroup = group;
    notifyListeners();
  }

  Future<void> upsertHost(Host host) => _mutate(
    (workspace) => workspace.copyWith(
      hosts: [...workspace.hosts.where((h) => h.id != host.id), host],
    ),
  );
  Future<void> deleteHost(String id) => _mutate(
    (workspace) => workspace.copyWith(
      hosts: workspace.hosts.where((h) => h.id != id).toList(),
      forwards: workspace.forwards.where((f) => f.hostId != id).toList(),
    ),
  );
  Future<void> upsertIdentity(Identity identity) => _mutate(
    (workspace) => workspace.copyWith(
      identities: [
        ...workspace.identities.where((i) => i.id != identity.id),
        identity,
      ],
    ),
  );
  Future<void> deleteIdentity(String id) => _mutate(
    (workspace) => workspace.copyWith(
      identities: workspace.identities.where((i) => i.id != id).toList(),
      hosts: workspace.hosts
          .map(
            (h) => h.identityId == id
                ? Host(
                    id: h.id,
                    label: h.label,
                    address: h.address,
                    port: h.port,
                    username: h.username,
                    group: h.group,
                    tags: h.tags,
                    notes: h.notes,
                    favorite: h.favorite,
                  )
                : h,
          )
          .toList(),
    ),
  );
  Future<void> upsertSnippet(Snippet snippet) => _mutate(
    (workspace) => workspace.copyWith(
      snippets: [
        ...workspace.snippets.where((s) => s.id != snippet.id),
        snippet,
      ],
    ),
  );
  Future<void> deleteSnippet(String id) => _mutate(
    (workspace) => workspace.copyWith(
      snippets: workspace.snippets.where((s) => s.id != id).toList(),
    ),
  );
  Future<void> upsertForward(ForwardRule rule) => _mutate(
    (workspace) => workspace.copyWith(
      forwards: [...workspace.forwards.where((f) => f.id != rule.id), rule],
    ),
  );
  Future<void> deleteForward(String id) => _mutate(
    (workspace) => workspace.copyWith(
      forwards: workspace.forwards.where((f) => f.id != id).toList(),
    ),
  );
  Future<void> trustHost(String address, String fingerprint) => _mutate(
    (workspace) => workspace.copyWith(
      knownHosts: {...workspace.knownHosts, address: fingerprint},
    ),
  );
  Future<void> updateSettings(Map<String, dynamic> settings) => _mutate(
    (workspace) =>
        workspace.copyWith(settings: {...workspace.settings, ...settings}),
  );
  Future<void> recordHistory(String entry) => _mutate(
    (workspace) => workspace.copyWith(
      history: [entry, ...workspace.history].take(100).toList(),
    ),
  );
  Future<void> changePassword(String oldPassword, String newPassword) =>
      _enqueue(() => repository.changePassword(oldPassword, newPassword));

  Future<void> exportTo(File file) => _enqueue(() => repository.exportTo(file));
  Future<Uint8List> exportBytes() async {
    await _mutations;
    return repository.exportBytes();
  }

  Future<void> restoreFrom(File file, String password) async {
    _generation++;
    await repository.restoreFrom(file, password);
    notifyListeners();
  }

  Future<void> importFrom(File file, String password) =>
      _enqueue(() => repository.importFrom(file, password));
}
