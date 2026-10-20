// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/models.dart';

typedef HostKeyVerifier = Future<bool> Function(
  String host,
  String fingerprint,
);

/// Every connection owns its socket, authentication, channels and listeners.
class SshService {
  Future<SshConnection> connect({
    required Host host,
    Identity? identity,
    required HostKeyVerifier verifyHostKey,
    void Function(SshConnection)? onConnecting,
  }) async {
    if (host.address.trim().isEmpty || host.port < 1 || host.port > 65535) {
      throw ArgumentError(
        'A host address and port from 1 to 65535 are required.',
      );
    }
    final keys = identity != null && identity.privateKey.trim().isNotEmpty
        ? SSHKeyPair.fromPem(
            identity.privateKey,
            identity.passphrase.isEmpty ? null : identity.passphrase,
          )
        : <SSHKeyPair>[];
    final socket = await SSHSocket.connect(
      host.address,
      host.port,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: identity != null && identity.username.isNotEmpty
          ? identity.username
          : host.username,
      identities: keys,
      onPasswordRequest: () => identity?.password,
      onVerifyHostKey: (type, fingerprint) => verifyHostKey(
        '${host.address}:${host.port}',
        '$type ${utf8.decode(fingerprint)}',
      ),
      keepAliveInterval: const Duration(seconds: 30),
    );
    final connection = SshConnection(client);
    try {
      onConnecting?.call(connection);
      await client.authenticated.timeout(const Duration(seconds: 60));
      return connection;
    } catch (_) {
      try {
        await client.close();
      } on SocketException {
        /* Preserve the authentication error. */
      }
      rethrow;
    }
  }
}

class SshConnection {
  SshConnection(this.client);
  final SSHClient client;
  final List<LocalForward> _forwards = [];
  final List<SSHSession> _shells = [];
  Future<SftpClient>? _sftp;
  bool _closed = false;
  Future<void>? _closeFuture;
  bool get isClosed => _closed;
  Future<SSHSession> openShell() async {
    final shell = await client.shell(
      pty: const SSHPtyConfig(type: 'xterm-256color'),
    );
    _shells.add(shell);
    return shell;
  }

  Future<SftpClient> sftp() => _sftp ??= client.sftp();

  Future<LocalForward> forwardLocal({
    required int bindPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    if (_closed) throw StateError('Connection closed');
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      bindPort,
    );
    if (_closed) {
      await server.close();
      throw StateError('Connection closed while binding forward');
    }
    final forward = LocalForward(server, client, remoteHost, remotePort);
    _forwards.add(forward);
    return forward;
  }

  Future<void> upload(
    String localPath,
    String remotePath, {
    void Function(int)? onProgress,
  }) async {
    final remote = await (await sftp()).open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await remote
          .write(
            File(localPath).openRead().map(Uint8List.fromList),
            onProgress: onProgress,
          )
          .done;
    } finally {
      await remote.close();
    }
  }

  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int)? onProgress,
  }) async {
    final remote = await (await sftp()).open(remotePath);
    final output = await File(localPath).open(mode: FileMode.write);
    try {
      await for (final chunk in remote.read(onProgress: onProgress)) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
      await remote.close();
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final forward in _forwards) {
      await forward.close();
    }
    for (final shell in _shells) {
      shell.close();
    }
    if (_sftp != null) {
      try {
        await _sftp!
            .then((sftp) => sftp.close())
            .timeout(const Duration(seconds: 1));
      } catch (_) {
        /* Transport may have already failed. */
      }
    }
    try {
      await client.close();
    } on SocketException {
      /* Closing an already reset transport is complete. */
    }
  }
}

class LocalForward {
  LocalForward(this._server, SSHClient client, String target, int port) {
    _subscription = _server.listen(
      (socket) async {
        _sockets.add(socket);
        try {
          final channel = await client.forwardLocal(target, port);
          if (_closed) {
            channel.destroy();
            socket.destroy();
            return;
          }
          _channels.add(channel);
          unawaited(
            socket.cast<List<int>>().pipe(channel.sink).catchError((Object _) {
              socket.destroy();
            }),
          );
          unawaited(
            channel.stream.cast<List<int>>().pipe(socket).catchError((
              Object _,
            ) {
              socket.destroy();
            }),
          );
        } catch (error) {
          if (!_closed) _errors.add(error);
          socket.destroy();
        }
      },
      onError: (Object error) {
        if (!_closed) _errors.add(error);
      },
    );
  }
  final ServerSocket _server;
  late final StreamSubscription<Socket> _subscription;
  final _sockets = <Socket>[];
  final _channels = <SSHForwardChannel>[];
  final _errors = StreamController<Object>.broadcast();
  bool _closed = false;
  int get port => _server.port;
  Stream<Object> get errors => _errors.stream;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _server.close();
    for (final socket in _sockets) {
      socket.destroy();
    }
    for (final channel in _channels) {
      channel.destroy();
    }
    await _errors.close();
  }
}
