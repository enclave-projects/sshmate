// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../data/ssh_service.dart';
import '../domain/models.dart';
import 'sftp_pane.dart';
import 'design_system.dart';

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.host,
    this.identity,
    required this.verifyHostKey,
    this.onClosed,
    this.onConnected,
    this.initialSftp = false,
    this.isVisible = true,
  });
  final Host host;
  final Identity? identity;
  final HostKeyVerifier verifyHostKey;
  final VoidCallback? onClosed;
  final ValueChanged<SshConnection>? onConnected;
  final bool initialSftp;
  final bool isVisible;
  @override
  State<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends State<TerminalPane> {
  final _terminal = Terminal(maxLines: 10000);
  final _focusNode = FocusNode(debugLabel: 'SSH terminal');
  final _subscriptions = <StreamSubscription<String>>[];
  SshConnection? _connection;
  SSHSession? _shell;
  late bool _files;
  bool _cancelled = false;
  bool _active = false;
  bool _connecting = true;
  bool _disposed = false;
  String _status = 'Connecting…';
  @override
  void initState() {
    super.initState();
    _files = widget.initialSftp;
    _terminal.onOutput = send;
    _terminal.onResize = (w, h, pw, ph) => _shell?.resizeTerminal(w, h, pw, ph);
    unawaited(_connect());
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _focusTerminal();
    if (!widget.isVisible) _focusNode.unfocus();
  }

  void _focusTerminal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed && widget.isVisible && _active && !_files) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _connect() async {
    try {
      final connection = await SshService().connect(
        host: widget.host,
        identity: widget.identity,
        onConnecting: (connection) {
          _connection = connection;
          if (_cancelled) unawaited(connection.close());
        },
        verifyHostKey: (host, key) async =>
            !_cancelled && await widget.verifyHostKey(host, key),
      );
      if (_cancelled) {
        await connection.close();
        return;
      }
      _connection = connection;
      widget.onConnected?.call(connection);
      _shell = await connection.openShell();
      if (_cancelled) {
        await connection.close();
        return;
      }
      _subscriptions.add(
        _shell!.stdout
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(_terminal.write, onError: _fail),
      );
      _subscriptions.add(
        _shell!.stderr
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(_terminal.write, onError: _fail),
      );
      _shell!.resizeTerminal(_terminal.viewWidth, _terminal.viewHeight);
      if (mounted) {
        setState(() {
          _active = true;
          _connecting = false;
          _status = 'Connected · encrypted SSH';
        });
        _focusTerminal();
      }
      await _shell!.done;
      await connection.close();
      if (mounted && !_cancelled) {
        setState(() {
          _active = false;
          _status = 'Session ended';
        });
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (mounted && !_cancelled) {
      setState(() {
        _active = false;
        _connecting = false;
        _status = 'Connection error: $error';
      });
    }
    unawaited(_connection?.close());
  }

  void send(String text) {
    if (_active && !_cancelled) _shell?.stdin.add(utf8.encode(text));
  }

  Future<void> disconnect() async {
    _cancelled = true;
    _active = false;
    _connecting = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _connection?.close();
    if (mounted && !_disposed) setState(() => _status = 'Disconnected');
  }

  @override
  void dispose() {
    _disposed = true;
    _focusNode.dispose();
    unawaited(disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !widget.isVisible,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: _active
                    ? const Color(0xff65cca7)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.host.username}@${widget.host.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_active && !_connecting)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _cancelled = false;
                      _connecting = true;
                      _status = 'Connecting…';
                    });
                    unawaited(_connect());
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconnect'),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: !_files
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                onPressed: () {
                  setState(() => _files = false);
                  _focusTerminal();
                },
                icon: const Icon(Icons.terminal),
                label: const Text('Terminal'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: _files
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                onPressed: () {
                  _focusNode.unfocus();
                  setState(() => _files = true);
                },
                icon: const Icon(Icons.folder_outlined),
                label: const Text('SFTP'),
              ),
              IconButton(
                tooltip: 'Disconnect',
                onPressed: () async {
                  await disconnect();
                  widget.onClosed?.call();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (_connecting) const LinearProgressIndicator(minHeight: 2),
        if (!_active && !_connecting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: MateNotice(
              '$_status. Use Reconnect to start another session.',
              error: _status.startsWith('Connection error'),
            ),
          ),
        Expanded(
          child: _files
              ? (!_active
                    ? Center(
                        child: Text(
                          _connecting
                              ? 'Waiting for SSH connection…'
                              : 'Reconnect to browse remote files.',
                        ),
                      )
                    : SftpPane(connection: _connection!))
              : TerminalView(
                  _terminal,
                  focusNode: _focusNode,
                  autofocus: false,
                  readOnly: !_active,
                  padding: const EdgeInsets.all(12),
                ),
        ),
      ],
    ),
  );
}
