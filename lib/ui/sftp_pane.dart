// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/ssh_service.dart';
import 'design_system.dart';

class SftpPane extends StatefulWidget {
  const SftpPane({super.key, required this.connection});
  final SshConnection connection;
  @override
  State<SftpPane> createState() => _SftpPaneState();
}

class _SftpPaneState extends State<SftpPane> {
  final _path = TextEditingController(text: '.');
  List<SftpName> _entries = [];
  bool _busy = false;
  String _status = '';
  bool _error = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  String _join(String name) =>
      '${_path.text.replaceFirst(RegExp(r'/+$'), '')}/$name';
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _status = '';
      _error = false;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '$error';
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(_list);
  Future<void> _list() async {
    if (!mounted) return;
    final requestedPath = _path.text;
    final sftp = await widget.connection.sftp();
    if (!mounted) return;
    final path = await sftp.absolute(requestedPath);
    final entries = await sftp.listdir(path);
    entries.removeWhere((e) => e.filename == '.' || e.filename == '..');
    entries.sort(
      (a, b) => a.attr.isDirectory == b.attr.isDirectory
          ? a.filename.compareTo(b.filename)
          : a.attr.isDirectory
          ? -1
          : 1,
    );
    if (mounted) {
      setState(() {
        _path.text = path;
        _entries = entries;
      });
    }
  }

  Future<String?> _name(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final value = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (!mounted) return null;
    if (value == null || value.isEmpty) return null;
    if (value.contains('/') || value == '.' || value == '..') {
      throw ArgumentError('Enter a single file name.');
    }
    return value;
  }

  Future<void> _upload() => _run(() async {
    final selection = await FilePicker.pickFiles();
    if (!mounted) return;
    if (selection.isEmpty || selection.single.path == null) return;
    final file = selection.single;
    final remotePath = _join(file.name);
    // Never silently overwrite a remote file.
    final existing = _entries.any((entry) => entry.filename == file.name);
    if (existing && !await _confirm('Replace ${file.name}?')) return;
    await widget.connection.upload(
      file.path!,
      remotePath,
      onProgress: _progress,
    );
    await _list();
    if (mounted) setState(() => _status = '${file.name} uploaded.');
  });
  void _progress(int bytes) {
    if (mounted) setState(() => _status = '${_size(bytes)} transferred…');
  }

  Future<bool> _confirm(String title) async => !mounted
      ? false
      : await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(title),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ) ??
            false;
  Future<void> _action(SftpName entry, String action) => _run(() async {
    final path = _join(entry.filename);
    final sftp = await widget.connection.sftp();
    if (!mounted) return;
    if (action == 'download') {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Download into directory',
      );
      if (!mounted) return;
      if (directory != null) {
        if (entry.filename.contains('/') ||
            entry.filename.contains('\\') ||
            entry.filename.contains(':')) {
          throw StateError('Remote name is not a safe local file name.');
        }
        final destination =
            '$directory${Platform.pathSeparator}${entry.filename}';
        if (await File(destination).exists() &&
            !await _confirm('Replace ${entry.filename}?')) {
          return;
        }
        await widget.connection.download(
          path,
          destination,
          onProgress: _progress,
        );
        if (mounted) setState(() => _status = '${entry.filename} downloaded.');
      }
    } else if (action == 'rename') {
      final name = await _name('Rename', initial: entry.filename);
      if (name != null) await sftp.rename(path, _join(name));
    } else if (action == 'delete' &&
        await _confirm('Delete ${entry.filename}?')) {
      if (entry.attr.isDirectory) {
        await sftp.rmdir(path);
      } else {
        await sftp.remove(path);
      }
    }
    await _list();
  });
  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Parent directory',
              onPressed: _busy
                  ? null
                  : () {
                      _path.text = _join('..');
                      _refresh();
                    },
              icon: const Icon(Icons.arrow_upward),
            ),
            Expanded(
              child: TextField(
                enabled: !_busy,
                controller: _path,
                onSubmitted: (_) => _refresh(),
                decoration: const InputDecoration(labelText: 'Remote path'),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.upload),
              label: const Text('Upload'),
            ),
            IconButton(
              tooltip: 'Create directory',
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final name = await _name('New directory');
                      if (name != null) {
                        await (await widget.connection.sftp()).mkdir(
                          _join(name),
                        );
                        await _list();
                      }
                    }),
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: MateNotice(_status, error: _error),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Text('REMOTE FILES', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text(
              '${_entries.length} items',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: _entries.isEmpty && !_busy && !_error
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_outlined, size: 40),
                    SizedBox(height: 12),
                    Text('This folder is empty'),
                    SizedBox(height: 6),
                    Text('Upload a file or create a directory to get started.'),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return ListTile(
                    leading: Icon(
                      entry.attr.isDirectory
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                    ),
                    title: Text(
                      entry.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      entry.attr.isDirectory
                          ? 'Directory'
                          : _size(entry.attr.size ?? 0),
                    ),
                    onTap: _busy || !entry.attr.isDirectory
                        ? null
                        : () {
                            _path.text = _join(entry.filename);
                            _refresh();
                          },
                    trailing: PopupMenuButton<String>(
                      tooltip: 'File actions',
                      enabled: !_busy,
                      onSelected: (action) => _action(entry, action),
                      itemBuilder: (_) => [
                        if (!entry.attr.isDirectory)
                          const PopupMenuItem(
                            value: 'download',
                            child: Text('Download'),
                          ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );
}
