// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import '../data/vault_repository.dart';
import 'theme.dart';
import 'design_system.dart';
import 'workspace_view.dart';

class SshMateApp extends StatefulWidget {
  const SshMateApp({super.key, required this.repository});
  final VaultRepository repository;
  @override
  State<SshMateApp> createState() => _SshMateAppState();
}

class _SshMateAppState extends State<SshMateApp> {
  bool light = false;
  late VaultRepository repository = widget.repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SSH Mate',
    debugShowCheckedModeBanner: false,
    theme: appTheme(light: light),
    home: VaultGate(
      key: ObjectKey(repository),
      repository: repository,
      onDirectory: (directory) => setState(() {
        repository.lock();
        repository = VaultRepository(directory: directory);
      }),
      onTheme: (value) => setState(() => light = value),
    ),
  );
}

class VaultGate extends StatefulWidget {
  const VaultGate({
    super.key,
    required this.repository,
    required this.onTheme,
    this.onDirectory,
  });
  final VaultRepository repository;
  final ValueChanged<bool> onTheme;
  final ValueChanged<Directory>? onDirectory;
  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> with WidgetsBindingObserver {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool? existing;
  bool busy = false;
  bool showPassword = false;
  bool unlocked = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    try {
      final value = await widget.repository.exists();
      if (mounted) setState(() => existing = value);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void _lock() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.repository.lock();
    password.clear();
    confirmation.clear();
    if (mounted) {
      setState(() {
        unlocked = false;
        existing = true;
      });
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    widget.repository.lock();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden &&
        unlocked &&
        widget.repository.workspace.settings['lockOnHide'] == true) {
      _lock();
    }
  }

  Future<void> _submit() async {
    if (busy || existing == null) return;
    if (!existing! &&
        (password.text.length < 12 || password.text != confirmation.text)) {
      setState(
        () => error = 'Use at least 12 characters and matching passwords.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (existing!) {
        await widget.repository.unlock(password.text);
      } else {
        await widget.repository.create(password.text);
      }
      password.clear();
      confirmation.clear();
      if (mounted) {
        widget.onTheme(widget.repository.workspace.settings['light'] == true);
        setState(() => unlocked = true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not open vault. Check your password and vault file.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    if (password.text.isEmpty) {
      setState(() => error = 'Enter the backup password first.');
      return;
    }
    final result = await FilePicker.pickFile(
      dialogTitle: 'Import encrypted SSH Mate vault',
    );
    if (result?.path == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.restoreFrom(File(result!.path!), password.text);
      password.clear();
      confirmation.clear();
      if (mounted) {
        setState(() {
          unlocked = true;
          existing = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not restore vault. Check the backup password and file.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.lock();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (unlocked) {
      return WorkspaceView(
        repository: widget.repository,
        onLock: _lock,
        onTheme: widget.onTheme,
      );
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ssh mate',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A calmer place to manage your servers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 42),
                Text(
                  existing == true ? 'Welcome back' : 'Create your local vault',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  existing == true
                      ? 'Unlock your encrypted workspace to continue.'
                      : 'Everything stays on this device. Choose a strong password; there is no account or password recovery.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('vault-password'),
                  controller: password,
                  obscureText: !showPassword,
                  enabled: !busy,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Vault password',
                    helperText: existing == false
                        ? 'At least 12 characters'
                        : null,
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      tooltip: showPassword ? 'Hide password' : 'Show password',
                      onPressed: () =>
                          setState(() => showPassword = !showPassword),
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (existing == false) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('vault-confirm'),
                    controller: confirmation,
                    obscureText: !showPassword,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: MateNotice(error!, error: true),
                  ),
                const SizedBox(height: 20),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                FilledButton(
                  key: const Key('vault-submit'),
                  onPressed: busy || existing == null ? null : _submit,
                  child: Text(
                    busy
                        ? 'Opening encrypted vault…'
                        : existing == true
                        ? 'Unlock workspace'
                        : 'Create vault',
                  ),
                ),
                if (existing == false)
                  TextButton(
                    onPressed: busy ? null : _restore,
                    child: const Text('Restore encrypted backup'),
                  ),
                if (widget.onDirectory != null)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final directory = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Choose an isolated vault folder',
                            );
                            if (directory != null && mounted) {
                              widget.onDirectory!(Directory(directory));
                            }
                          },
                    icon: const Icon(Icons.folder_outlined, size: 16),
                    label: const Text('Open or create another vault'),
                  ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OFFLINE BY DESIGN  ·  GPLv3',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
