// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:io';

import '../data/ssh_config_importer.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ssh_service.dart';
import '../data/vault_repository.dart';
import '../domain/models.dart';
import 'editors.dart';
import 'design_system.dart';
import 'terminal_pane.dart';
import 'theme.dart';
import 'workspace_controller.dart';

final sections = [
  'Hosts',
  'SFTP',
  'Snippets',
  'Port forwarding',
  'Keychain',
  'Known hosts',
  'History',
  'Settings',
];
final sectionIcons = [
  Icons.dns_outlined,
  Icons.folder_open,
  Icons.code,
  Icons.route,
  Icons.key_outlined,
  Icons.verified_user_outlined,
  Icons.history,
  Icons.settings_outlined,
];

class _SessionTab {
  _SessionTab(this.host, this.identity, this.sftp);
  final Host host;
  final Identity? identity;
  final bool sftp;
  final key = GlobalKey<TerminalPaneState>();
}

class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    super.key,
    required this.repository,
    required this.onLock,
    required this.onTheme,
  });
  final VaultRepository repository;
  final VoidCallback onLock;
  final ValueChanged<bool> onTheme;
  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  late final controller = WorkspaceController(repository: widget.repository);
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final sessions = <_SessionTab>[];
  final forwards = <String, (SshConnection, LocalForward)>{};
  final startingForwards = <String>{};
  final pendingConnections = <SshConnection>{};
  bool disposed = false;
  int section = 0;
  int activeTab = -1;
  bool listView = false;
  bool favorites = false;
  String? group;
  Workspace get workspace => controller.workspace;
  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Semantics(liveRegion: true, child: Text(text))),
        );
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) _message(success);
    } catch (e) {
      _message('Operation failed: $e');
    }
  }

  void _select(int value) {
    setState(() {
      section = value;
      activeTab = -1;
      search.clear();
      group = null;
    });
  }

  Future<void> _host([Host? host]) async {
    final result = await editHost(
      context,
      host: host,
      identities: workspace.identities,
    );
    if (result != null) {
      await _run(
        () => controller.upsertHost(result),
        success: 'Host saved to your vault.',
      );
    }
  }

  Future<bool> _verify(String address, String fingerprint) async {
    if (!mounted || !controller.isUnlocked) return false;
    final previous = workspace.knownHosts[address];
    if (previous == fingerprint) return true;
    if (previous != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Host key changed — connection blocked'),
          content: SelectableText(
            '$address\n\nSaved: $previous\n\nReceived: $fingerprint\n\nVerify the change independently. Remove the old key from Known hosts only after verification.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return false;
    }
    final accepted = await confirm(
      context,
      'Trust this host?',
      '$address\n\n$fingerprint\n\nVerify this fingerprint with the server administrator before continuing.',
      action: 'Trust and connect',
    );
    if (accepted && mounted && controller.isUnlocked) {
      await controller.trustHost(address, fingerprint);
      return true;
    }
    return false;
  }

  Future<Identity?> _credentials(Host host) async {
    for (final i in workspace.identities) {
      if (i.id == host.identityId) return i;
    }
    final result = await editFields(
      context,
      'Connect to ${host.label}',
      [const FieldSpec('SSH password', secret: true)],
      action: 'Connect',
      description: 'Used for this session only. Save a reusable key or password in Keychain.',
    );
    return result == null
        ? null
        : Identity(id: newId(), label: 'Session only', password: result[0]);
  }

  Future<void> _connect(Host host, {bool sftp = false}) async {
    final identity = await _credentials(host);
    if (identity == null || !mounted || !controller.isUnlocked) return;
    final tab = _SessionTab(host, identity, sftp);
    setState(() {
      sessions.add(tab);
      activeTab = sessions.length - 1;
    });
    await _run(
      () => controller.recordHistory(
        '${DateTime.now().toIso8601String()} · Opened ${sftp ? 'SFTP' : 'SSH'} · ${host.label} (${host.username}@${host.address}:${host.port})',
      ),
    );
  }

  void _closeTab(int index) {
    final tab = sessions[index];
    tab.key.currentState?.disconnect();
    setState(() {
      sessions.removeAt(index);
      if (activeTab == index) {
        activeTab = sessions.isEmpty
            ? -1
            : (index - 1).clamp(0, sessions.length - 1);
      } else if (activeTab > index) {
        activeTab--;
      }
    });
  }

  Future<void> _identity([Identity? identity]) async {
    final v = await editFields(
      context,
      identity == null ? 'New identity' : 'Edit identity',
      [
        FieldSpec('Label', value: identity?.label ?? '', required: true),
        FieldSpec('Username (optional)', value: identity?.username ?? ''),
        FieldSpec(
          'Private key (OpenSSH or PEM)',
          value: identity?.privateKey ?? '',
          lines: 5,
        ),
        FieldSpec(
          'Key passphrase',
          value: identity?.passphrase ?? '',
          secret: true,
        ),
        FieldSpec(
          'SSH password',
          value: identity?.password ?? '',
          secret: true,
        ),
      ],
      importKey: true,
      description: 'Credentials are encrypted inside your local vault.',
    );
    if (v != null) {
      await _run(
        () => controller.upsertIdentity(
          Identity(
            id: identity?.id ?? newId(),
            label: v[0],
            username: v[1],
            privateKey: v[2],
            passphrase: v[3],
            password: v[4],
          ),
        ),
      );
    }
  }

  Future<void> _snippet([Snippet? snippet]) async {
    final v = await editFields(
      context,
      snippet == null ? 'New snippet' : 'Edit snippet',
      [
        FieldSpec('Label', value: snippet?.label ?? '', required: true),
        FieldSpec(
          'Command',
          value: snippet?.command ?? '',
          lines: 5,
          required: true,
        ),
      ],
    );
    if (v != null) {
      await _run(
        () => controller.upsertSnippet(
          Snippet(id: snippet?.id ?? newId(), label: v[0], command: v[1]),
        ),
      );
    }
  }

  Future<void> _forward([ForwardRule? rule]) async {
    if (workspace.hosts.isEmpty) {
      _message('Add a host first.');
      return;
    }
    final selection = await showDialog<Host>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose SSH gateway'),
        children: workspace.hosts
            .map(
              (h) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, h),
                child: Text('${h.label} · ${h.address}'),
              ),
            )
            .toList(),
      ),
    );
    if (selection == null || !mounted) return;
    final v = await editFields(
      context,
      'Local port forward',
      [
        FieldSpec('Label', value: rule?.label ?? '', required: true),
        FieldSpec(
          'Local port (127.0.0.1)',
          value: '${rule?.localPort ?? 8080}',
          port: true,
        ),
        FieldSpec(
          'Destination hostname',
          value: rule?.remoteHost ?? '127.0.0.1',
          required: true,
        ),
        FieldSpec(
          'Destination port',
          value: '${rule?.remotePort ?? 80}',
          port: true,
        ),
      ],
      description:
          'Traffic goes through ${selection.label}. The listener is restricted to loopback.',
    );
    if (v != null) {
      await _run(
        () => controller.upsertForward(
          ForwardRule(
            id: rule?.id ?? newId(),
            label: v[0],
            hostId: selection.id,
            localPort: int.parse(v[1]),
            remoteHost: v[2],
            remotePort: int.parse(v[3]),
          ),
        ),
      );
    }
  }

  Future<void> _toggleForward(ForwardRule rule) async {
    if (forwards.containsKey(rule.id)) {
      final pair = forwards.remove(rule.id)!;
      await pair.$2.close();
      await pair.$1.close();
      if (mounted) setState(() {});
      return;
    }
    final host = workspace.hosts.where((h) => h.id == rule.hostId).firstOrNull;
    if (host == null || startingForwards.contains(rule.id)) return;
    final identity = await _credentials(host);
    if (identity == null || !mounted) return;
    setState(() => startingForwards.add(rule.id));
    SshConnection? connection;
    try {
      connection = await SshService().connect(
        host: host,
        identity: identity,
        verifyHostKey: _verify,
        onConnecting: (value) {
          if (disposed || !controller.isUnlocked) {
            unawaited(value.close());
          } else {
            pendingConnections.add(value);
          }
        },
      );
      if (disposed || !controller.isUnlocked) {
        await connection.close();
        return;
      }
      final forward = await connection.forwardLocal(
        bindPort: rule.localPort,
        remoteHost: rule.remoteHost,
        remotePort: rule.remotePort,
      );
      if (!mounted || !controller.isUnlocked) {
        await forward.close();
        await connection.close();
        return;
      }
      forwards[rule.id] = (connection, forward);
      forward.errors.listen(
        (error) => _message('Forward ${rule.label}: $error'),
      );
    } catch (e) {
      await connection?.close();
      _message('Could not start forward: $e');
    } finally {
      if (connection != null) pendingConnections.remove(connection);
      startingForwards.remove(rule.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _importConfig() => _run(() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import OpenSSH config',
    );
    if (picked?.path == null) return;
    final file = File(picked!.path!);
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('Config file exceeds 2 MiB.');
    }
    final result = SshConfigImporter.parse(await file.readAsString());
    if (!mounted) return;
    final accepted = await confirm(
      context,
      'Import ${result.hosts.length} hosts?',
      '${result.hosts.map((h) => '${h.label} - ${h.address}:${h.port}').join('\n')}\n\n${result.warnings.join('\n')}',
      action: 'Import',
    );
    if (!accepted || !mounted) return;
    for (final host in result.hosts) {
      await controller.upsertHost(
        Host(
          id: '${newId()}-${host.id}',
          label: host.label,
          address: host.address,
          username: host.username,
          port: host.port,
          group: host.group,
          notes: host.notes,
        ),
      );
    }
    _message(
      'Imported ${result.hosts.length} hosts. Review usernames and assign identities before connecting.',
    );
  });

  Future<void> _importBackup() => _run(() async {
    if (sessions.isNotEmpty ||
        forwards.isNotEmpty ||
        startingForwards.isNotEmpty) {
      _message('Close sessions and stop forwards before replacing this vault.');
      return;
    }
    if (!await confirm(
      context,
      'Replace this workspace?',
      'Import replaces hosts, identities, snippets, rules and trusted host keys. Export a backup first.',
      action: 'Choose backup',
    )) {
      return;
    }
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import encrypted SSH Mate vault',
    );
    if (picked?.path == null || !mounted) return;
    final value = await editFields(context, 'Backup password', [
      const FieldSpec('Backup password', secret: true, required: true),
    ], action: 'Import');
    if (value == null) return;
    await controller.importFrom(File(picked!.path!), value[0]);
    if (mounted) {
      widget.onTheme(workspace.settings['light'] == true);
      _message('Encrypted backup imported.');
    }
  });

  Future<void> _changePassword() => _run(() async {
    final value = await editFields(context, 'Change vault password', [
      const FieldSpec('Current password', secret: true, required: true),
      const FieldSpec(
        'New password (at least 12 characters)',
        secret: true,
        required: true,
      ),
      const FieldSpec('Confirm new password', secret: true, required: true),
    ]);
    if (value == null) return;
    if (value[1] != value[2] || value[1].length < 12) {
      _message('New passwords must match and contain at least 12 characters.');
      return;
    }
    await widget.repository.changePassword(value[0], value[1]);
    _message(
      'Vault password changed. Existing exported backups retain their old password.',
    );
  });

  Future<void> _backup() async {
    await _run(() async {
      final bytes = await widget.repository.exportBytes();
      final result = await FilePicker.saveFile(
        dialogTitle: 'Export encrypted vault',
        fileName: 'ssh-mate-vault.json',
        bytes: bytes,
      );
      if (result != null) {
        _message('Encrypted backup saved. Keep your vault password safe.');
      }
    });
  }

  Future<void> _delete(String label, Future<void> Function() action) async {
    if (await confirm(
      context,
      'Delete $label?',
      'This removes it from the local vault.',
    )) {
      await _run(action, success: '$label deleted.');
    }
  }

  @override
  void dispose() {
    disposed = true;
    for (final connection in pendingConnections) {
      unawaited(connection.close());
    }
    for (final tab in sessions) {
      tab.key.currentState?.disconnect();
    }
    for (final pair in forwards.values) {
      unawaited(pair.$2.close());
      unawaited(pair.$1.close());
    }
    controller.removeListener(_changed);
    controller.dispose();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
        _select(0);
        searchFocus.requestFocus();
      },
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
          _host(),
      const SingleActivator(LogicalKeyboardKey.tab, control: true): () {
        if (sessions.isNotEmpty) {
          setState(() => activeTab = (activeTab + 1) % sessions.length);
        }
      },
      const SingleActivator(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      ): () {
        if (sessions.isNotEmpty) {
          setState(() => activeTab = (activeTab - 1) % sessions.length);
        }
      },
      const SingleActivator(
        LogicalKeyboardKey.keyW,
        control: true,
        shift: true,
      ): () {
        if (activeTab >= 0) _closeTab(activeTab);
      },
      const SingleActivator(
        LogicalKeyboardKey.keyL,
        control: true,
        shift: true,
      ): widget.onLock,
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            return Row(
              children: [
                SizedBox(width: wide ? 236 : 76, child: _sidebar(wide)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _tabs(),
                      Expanded(
                        child: IndexedStack(
                          index: activeTab + 1,
                          children: [
                            _page(),
                            for (final tab in sessions)
                              TerminalPane(
                                key: tab.key,
                                host: tab.host,
                                identity: tab.identity,
                                verifyHostKey: _verify,
                                initialSftp: tab.sftp,
                                isVisible:
                                    activeTab >= 0 &&
                                    identical(sessions[activeTab], tab),
                              ),
                          ],
                        ),
                      ),
                      _status(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  Widget _sidebar(bool wide) => ColoredBox(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff0d141c)
        : const Color(0xffedf1f7),
    child: Column(
      children: [
        const SizedBox(height: 25),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Row(
            children: [
              Icon(
                Icons.terminal_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 29,
              ),
              if (wide) ...[
                const SizedBox(width: 11),
                const Expanded(
                  child: Text(
                    'ssh mate',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Personal vault',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: sections.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Tooltip(
                message: sections[i],
                child: AnimatedContainer(
                  duration: MateMotion.duration(context),
                  decoration: BoxDecoration(
                    color: section == i && activeTab < 0
                        ? accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _select(i),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 14 : 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sectionIcons[i],
                              size: 20,
                              color: section == i
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            ),
                            if (wide) ...[
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  sections[i],
                                  style: TextStyle(
                                    color: section == i
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                              if (i == 0)
                                Text(
                                  '${workspace.hosts.length}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (wide)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your private workspace',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Encrypted on this device.\nReady whenever you are.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(9),
          child: wide
              ? TextButton.icon(
                  onPressed: widget.onLock,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text(
                    'Lock workspace',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              : IconButton(
                  onPressed: widget.onLock,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  tooltip: 'Lock workspace',
                ),
        ),
      ],
    ),
  );
  Widget _tabs() => Container(
    height: 54,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        TextButton.icon(
          onPressed: () => setState(() => activeTab = -1),
          icon: const Icon(Icons.grid_view, size: 15),
          label: const Text('Workspace'),
        ),
        const VerticalDivider(width: 1, indent: 12, endIndent: 12),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: sessions.length,
            itemBuilder: (context, i) => Container(
              decoration: BoxDecoration(
                color: i == activeTab ? accent.withValues(alpha: 0.08) : null,
                border: Border(
                  bottom: BorderSide(
                    color: i == activeTab
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => activeTab = i),
                    icon: Icon(
                      sessions[i].sftp ? Icons.folder_open : Icons.terminal,
                      size: 15,
                    ),
                    label: Text(sessions[i].host.label),
                  ),
                  IconButton(
                    onPressed: () => _closeTab(i),
                    icon: const Icon(Icons.close, size: 14),
                    tooltip: 'Close session',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _status() => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          color: Theme.of(context).colorScheme.primary,
          size: 6,
        ),
        const SizedBox(width: 7),
        Text(
          'Local encrypted vault',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        const Spacer(),
        Text(
          '${sessions.length} tabs  ·  ${forwards.length} forwards  ·  GPLv3',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
  Widget _page() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sections[section],
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _subtitle(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if ([0, 2, 3, 4].contains(section))
              FilledButton.icon(
                onPressed: () {
                  switch (section) {
                    case 0:
                      _host();
                    case 2:
                      _snippet();
                    case 3:
                      _forward();
                    case 4:
                      _identity();
                  }
                },
                icon: const Icon(Icons.add, size: 17),
                label: Text(
                  [
                    'New host',
                    '',
                    'New snippet',
                    'New rule',
                    'New identity',
                  ][section],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (section == 0 || section == 1) _hostToolbar(),
        Expanded(
          child: switch (section) {
            0 || 1 => _hosts(),
            2 => _snippets(),
            3 => _forwards(),
            4 => _identities(),
            5 => _knownHosts(),
            6 => _history(),
            _ => _settings(),
          },
        ),
      ],
    ),
  );
  String _subtitle() => switch (section) {
    0 => 'All your connections, in one place.',
    1 => 'Browse and transfer files over an encrypted SSH connection.',
    2 => 'Keep useful commands close at hand.',
    3 => 'Secure tunnels through your SSH gateways.',
    4 => 'Reusable credentials, encrypted in your vault.',
    5 => 'Server fingerprints you have explicitly trusted.',
    6 => 'Local connection activity. Terminal output is never recorded.',
    _ => 'Make this workspace your own.',
  };
  Widget _hostToolbar() => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                focusNode: searchFocus,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search hosts, addresses, or tags',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: search.text.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text('Ctrl K', style: TextStyle(fontSize: 12)),
                        )
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(search.clear),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => setState(() => listView = !listView),
              icon: Icon(listView ? Icons.grid_view : Icons.view_list),
              tooltip: 'Switch view',
            ),
          ],
        ),
        const SizedBox(height: 13),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              FilterChip(
                label: const Text('All hosts'),
                selected: group == null && !favorites,
                onSelected: (_) => setState(() {
                  group = null;
                  favorites = false;
                }),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Favorites'),
                avatar: const Icon(Icons.star_border, size: 15),
                selected: favorites,
                onSelected: (v) => setState(() => favorites = v),
              ),
              for (final g
                  in workspace.hosts
                      .map((h) => h.group)
                      .where((g) => g.isNotEmpty)
                      .toSet())
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    label: Text(g),
                    selected: group == g,
                    onSelected: (v) => setState(() => group = v ? g : null),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _empty(
    IconData icon,
    String title,
    String detail, {
    String? action,
    VoidCallback? onAction,
  }) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: .07),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 17),
                label: Text(action),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _hosts() {
    final query = search.text.toLowerCase();
    final hosts =
        workspace.hosts
            .where(
              (h) =>
                  (!favorites || h.favorite) &&
                  (group == null || h.group == group) &&
                  '${h.label} ${h.address} ${h.username} ${h.tags.join(' ')}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList()
          ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          );
    if (hosts.isEmpty) {
      return _empty(
        Icons.dns_outlined,
        workspace.hosts.isEmpty
            ? 'Your next connection starts here'
            : 'No matching hosts',
        workspace.hosts.isEmpty
            ? 'Add your first server, organize it with groups and tags, and connect on your terms.'
            : 'Try another search or clear your filters.',
        action: workspace.hosts.isEmpty ? 'Add a host' : 'Clear filters',
        onAction: workspace.hosts.isEmpty
            ? () => _host()
            : () => setState(() {
                search.clear();
                group = null;
                favorites = false;
              }),
      );
    }
    if (listView) {
      return ListView.builder(
        itemCount: hosts.length,
        itemBuilder: (context, i) {
          final h = hosts[i];
          return Card(
            child: ListTile(
              leading: Icon(
                Icons.dns_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(h.label),
              subtitle: Text('${h.username}@${h.address}:${h.port}'),
              onTap: () => _connect(h, sftp: section == 1),
              trailing: _hostMenu(h),
            ),
          );
        },
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 206,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: hosts.length,
      itemBuilder: (context, i) {
        final h = hosts[i];
        return MateSurface(
          onTap: () => _connect(h, sftp: section == 1),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.dns_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 21,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _run(
                        () => controller.upsertHost(
                          h.copyWith(favorite: !h.favorite),
                        ),
                      ),
                      icon: Icon(
                        h.favorite ? Icons.star : Icons.star_border,
                        size: 18,
                        color: h.favorite
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Favorite',
                    ),
                    _hostMenu(h),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  h.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${h.username}@${h.address}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  h.tags.isEmpty
                      ? (h.group.isEmpty ? 'SSH  ·  ${h.port}' : h.group)
                      : h.tags.map((t) => '#$t').join('  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      section == 1 ? Icons.folder_open : Icons.terminal,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      section == 1 ? 'Browse files' : 'Connect SSH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hostMenu(Host host) => PopupMenuButton<String>(
    tooltip: 'Host actions',
    icon: const Icon(Icons.more_horiz, size: 18),
    onSelected: (value) {
      switch (value) {
        case 'connect':
          _connect(host);
        case 'sftp':
          _connect(host, sftp: true);
        case 'edit':
          _host(host);
        case 'duplicate':
          _run(
            () => controller.upsertHost(
              Host(
                id: newId(),
                label: '${host.label} copy',
                address: host.address,
                username: host.username,
                port: host.port,
                group: host.group,
                tags: host.tags,
                notes: host.notes,
                identityId: host.identityId,
              ),
            ),
          );
        case 'delete':
          _delete(host.label, () => controller.deleteHost(host.id));
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'connect', child: Text('Connect SSH')),
      const PopupMenuItem(value: 'sftp', child: Text('Open SFTP')),
      const PopupMenuItem(value: 'edit', child: Text('Edit')),
      const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
      const PopupMenuItem(value: 'delete', child: Text('Delete')),
    ],
  );
  Widget _identities() => workspace.identities.isEmpty
      ? _empty(
          Icons.key_outlined,
          'Bring your own keys',
          'Store SSH passwords and private keys once, then assign them to your hosts.',
          action: 'Add identity',
          onAction: _identity,
        )
      : ListView.builder(
          itemCount: workspace.identities.length,
          itemBuilder: (context, i) {
            final identity = workspace.identities[i];
            return Card(
              child: ListTile(
                leading: Icon(
                  Icons.key,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(identity.label),
                subtitle: Text(
                  identity.privateKey.isEmpty
                      ? 'Password identity'
                      : 'Private key identity',
                ),
                onTap: () => _identity(identity),
                trailing: IconButton(
                  onPressed: () => _delete(
                    identity.label,
                    () => controller.deleteIdentity(identity.id),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete identity',
                ),
              ),
            );
          },
        );
  Widget _snippets() => workspace.snippets.isEmpty
      ? _empty(
          Icons.code,
          'Save a little time',
          'Save commands you use often. Copy them or send them to a selected terminal for review.',
          action: 'Add snippet',
          onAction: _snippet,
        )
      : ListView.builder(
          itemCount: workspace.snippets.length,
          itemBuilder: (context, i) {
            final s = workspace.snippets[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _snippet(s),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit snippet',
                        ),
                        IconButton(
                          onPressed: () => _delete(
                            s.label,
                            () => controller.deleteSnippet(s.id),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Delete snippet',
                        ),
                      ],
                    ),
                    SelectableText(
                      s.command,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: s.command));
                            _message('Copied command to clipboard.');
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy'),
                        ),
                        OutlinedButton.icon(
                          onPressed: sessions.isEmpty
                              ? null
                              : () async {
                                  final tab = await showDialog<_SessionTab>(
                                    context: context,
                                    builder: (context) => SimpleDialog(
                                      title: const Text('Send to terminal'),
                                      children: sessions
                                          .map(
                                            (t) => SimpleDialogOption(
                                              onPressed: () =>
                                                  Navigator.pop(context, t),
                                              child: Text(t.host.label),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  );
                                  if (tab != null &&
                                      context.mounted &&
                                      await confirm(
                                        context,
                                        'Send command?',
                                        '${s.command}\n\nNewlines in a snippet may execute commands immediately. Review before sending.',
                                        action: 'Send',
                                      )) {
                                    tab.key.currentState?.send(s.command);
                                    if (mounted) {
                                      setState(
                                        () => activeTab = sessions.indexOf(tab),
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.terminal, size: 16),
                          label: const Text('Send to terminal'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
  Widget _forwards() => workspace.forwards.isEmpty
      ? _empty(
          Icons.route,
          'A secure path to your services',
          'Forward a local loopback port through an SSH host. Each tunnel owns an independent connection.',
          action: 'Add rule',
          onAction: _forward,
        )
      : ListView.builder(
          itemCount: workspace.forwards.length,
          itemBuilder: (context, i) {
            final rule = workspace.forwards[i];
            final running = forwards.containsKey(rule.id);
            return Card(
              child: ListTile(
                leading: Icon(
                  Icons.route,
                  color: running
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(rule.label),
                subtitle: Text(
                  '127.0.0.1:${rule.localPort} → ${rule.remoteHost}:${rule.remotePort}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: startingForwards.contains(rule.id)
                          ? null
                          : () => _toggleForward(rule),
                      child: Text(
                        startingForwards.contains(rule.id)
                            ? 'Starting…'
                            : running
                            ? 'Stop'
                            : 'Start',
                      ),
                    ),
                    IconButton(
                      onPressed: running ? null : () => _forward(rule),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit rule',
                    ),
                    IconButton(
                      onPressed: running
                          ? null
                          : () => _delete(
                              rule.label,
                              () => controller.deleteForward(rule.id),
                            ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete rule',
                    ),
                  ],
                ),
              ),
            );
          },
        );
  Widget _knownHosts() => workspace.knownHosts.isEmpty
      ? _empty(
          Icons.verified_user_outlined,
          'Trust starts with verification',
          'Verified server fingerprints appear here after your first connection.',
        )
      : ListView(
          children: workspace.knownHosts.entries
              .map(
                (entry) => Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.verified_user_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(entry.key),
                    subtitle: SelectableText(
                      entry.value,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Forget fingerprint',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(
                        entry.key,
                        () => controller.save(
                          workspace.copyWith(
                            knownHosts: {...workspace.knownHosts}
                              ..remove(entry.key),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
  Widget _history() => workspace.history.isEmpty
      ? _empty(
          Icons.history,
          'No connections yet',
          'Connection attempts appear here. Commands, passwords, and terminal output are not logged.',
        )
      : Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _delete(
                  'connection history',
                  () => controller.save(workspace.copyWith(history: [])),
                ),
                child: const Text('Clear history'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: workspace.history.length,
                itemBuilder: (context, i) => ListTile(
                  leading: Icon(
                    Icons.terminal,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    workspace.history[i],
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        );
  Widget _settings() => ListView(
    children: [
      const MateSectionLabel('Appearance & behavior'),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Light appearance'),
              subtitle: const Text('A lighter workspace around your terminal.'),
              value: workspace.settings['light'] == true,
              onChanged: (v) => _run(() async {
                await controller.updateSettings({'light': v});
                widget.onTheme(v);
              }),
            ),
            SwitchListTile(
              title: const Text('Lock when hidden'),
              subtitle: const Text(
                'Close sessions and lock when the app is minimized or hidden.',
              ),
              value: workspace.settings['lockOnHide'] == true,
              onChanged: (v) =>
                  _run(() => controller.updateSettings({'lockOnHide': v})),
            ),
          ],
        ),
      ),
      const MateSectionLabel('Vault & portability'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('Export encrypted backup'),
          subtitle: const Text(
            'Portable JSON envelope. Protected by your vault password.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _backup,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Import OpenSSH config'),
          subtitle: const Text(
            'Preview literal host entries. Imported directives never execute.',
          ),
          onTap: _importConfig,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Import encrypted backup'),
          subtitle: const Text(
            'Replace this workspace from a portable SSH Mate vault.',
          ),
          onTap: _importBackup,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change vault password'),
          subtitle: const Text('Re-encrypt the local vault with a new key.'),
          onTap: _changePassword,
        ),
      ),
      const MateSectionLabel('Help & about'),
      const Card(
        child: ListTile(
          leading: Icon(Icons.keyboard_outlined),
          title: Text('Keyboard shortcuts'),
          subtitle: Text(
            'Ctrl K · Search hosts\nCtrl N · New host\nCtrl Shift L · Lock workspace',
            style: TextStyle(height: 1.8),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('SSH Mate · 0.2.0'),
          subtitle: const Text(
            'GNU GPLv3 · Independent open source SSH workspace\nNo cloud account, subscriptions, telemetry, or automatic sync.',
            style: TextStyle(height: 1.8),
          ),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'SSH Mate',
            applicationVersion: '0.2.0',
          ),
        ),
      ),
    ],
  );
}
