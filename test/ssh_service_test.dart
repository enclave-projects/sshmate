// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshmate/data/ssh_service.dart';
import 'package:sshmate/domain/models.dart';

void main() {
  test('invalid endpoints fail before opening a socket', () async {
    await expectLater(
      SshService().connect(
        host: Host(id: 'bad', label: 'Bad', address: '', port: 0),
        verifyHostKey: (_, _) async => true,
      ),
      throwsArgumentError,
    );
  });

  group('real isolated loopback SSH and SFTP', () {
    late Process server;
    late Host host;
    late String privateKey;
    const identity = Identity(
      id: 'fixture',
      label: 'Fixture',
      username: 'fixture',
      password: 'test-only',
    );
    setUpAll(() async {
      server = await Process.start('python', ['test/fixtures/ssh_loopback.py']);
      final errors = StringBuffer();
      server.stderr.transform(utf8.decoder).listen(errors.write);
      final line = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw StateError(
              'Install fixture dependency: python -m pip install paramiko. $errors',
            ),
          );
      final fixture = jsonDecode(line) as Map<String, dynamic>;
      privateKey = fixture['privateKey'] as String;
      host = Host(
        id: 'fixture',
        label: 'Loopback',
        address: '127.0.0.1',
        port: fixture['port'] as int,
        username: 'fixture',
      );
    });
    tearDownAll(() async {
      server.kill();
      await server.exitCode;
    });

    test('incorrect password fails without opening a session', () async {
      await expectLater(
        SshService().connect(
          host: host,
          identity: const Identity(
            id: 'wrong',
            label: 'Wrong',
            username: 'fixture',
            password: 'incorrect',
          ),
          verifyHostKey: (_, _) async => true,
        ),
        throwsA(anything),
      );
    });

    test('closing during host-key challenge cancels authentication', () async {
      final challenged = Completer<void>();
      final decision = Completer<bool>();
      late SshConnection connection;
      final pending = SshService().connect(
        host: host,
        identity: identity,
        onConnecting: (value) => connection = value,
        verifyHostKey: (_, _) {
          challenged.complete();
          return decision.future;
        },
      );
      final failure = expectLater(pending, throwsA(anything));
      await challenged.future.timeout(const Duration(seconds: 5));
      await connection.close();
      decision.complete(false);
      await failure;
      expect(connection.isClosed, isTrue);
    });

    test('key authentication and sessions stay isolated', () async {
      final first = await SshService().connect(
        host: host,
        identity: Identity(
          id: 'key',
          label: 'Temporary test key',
          username: 'fixture',
          privateKey: privateKey,
        ),
        verifyHostKey: (_, _) async => true,
      );
      final second = await SshService().connect(
        host: host,
        identity: identity,
        verifyHostKey: (_, _) async => true,
      );
      addTearDown(first.close);
      addTearDown(second.close);
      expect(first.client, isNot(same(second.client)));
      await first.close();
      final shell = await second.openShell();
      final response = shell.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .first;
      expect(
        await response.timeout(const Duration(seconds: 5)),
        contains('fixture-ready'),
      );
      expect(second.isClosed, isFalse);
    });

    test(
      'local tunnel forwards bytes and closes its listener with the session',
      () async {
        final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>[];
        final subscription = echo.listen((socket) {
          sockets.add(socket);
          socket.listen(socket.add, onDone: socket.destroy);
        });
        addTearDown(() async {
          for (final socket in sockets) {
            socket.destroy();
          }
          await subscription.cancel();
          await echo.close();
        });
        final connection = await SshService().connect(
          host: host,
          identity: identity,
          verifyHostKey: (_, _) async => true,
        );
        addTearDown(connection.close);
        final forward = await connection.forwardLocal(
          bindPort: 0,
          remoteHost: '127.0.0.1',
          remotePort: echo.port,
        );
        final socket = await Socket.connect('127.0.0.1', forward.port);
        addTearDown(socket.destroy);
        socket.add(utf8.encode('tunnel-roundtrip'));
        final bytes = await socket.first.timeout(const Duration(seconds: 5));
        expect(utf8.decode(bytes), 'tunnel-roundtrip');
        await connection.close();
        await expectLater(
          Socket.connect('127.0.0.1', forward.port),
          throwsA(isA<SocketException>()),
        );
      },
    );

    test('rejecting an unknown host key prevents authentication', () async {
      var asked = false;
      await expectLater(
        SshService().connect(
          host: host,
          identity: identity,
          verifyHostKey: (_, fingerprint) async {
            asked = true;
            expect(fingerprint, contains('SHA256:'));
            return false;
          },
        ),
        throwsA(anything),
      );
      expect(asked, isTrue);
    });

    test(
      'PTY output, upload, browse, download, rename and delete roundtrip',
      () async {
        final connection = await SshService().connect(
          host: host,
          identity: identity,
          verifyHostKey: (_, _) async => true,
        );
        addTearDown(connection.close);
        final shell = await connection.openShell();
        final output = StringBuffer();
        final echo = Completer<void>();
        final subscription = shell.stdout
            .cast<List<int>>()
            .transform(utf8.decoder)
            .listen((data) {
              output.write(data);
              if (output.toString().contains('hello-isolation')) {
                if (!echo.isCompleted) echo.complete();
              }
            });
        addTearDown(subscription.cancel);
        shell.resizeTerminal(100, 40);
        shell.stdin.add(utf8.encode('hello-isolation\n'));
        await echo.future.timeout(const Duration(seconds: 5));
        final temp = await Directory.systemTemp.createTemp('ssh-mate-test-');
        addTearDown(() => temp.delete(recursive: true));
        final original = File('${temp.path}/upload.txt');
        await original.writeAsString('SSH Mate encrypted transfer\n');
        final sftp = await connection.sftp();
        await sftp.mkdir('/roundtrip');
        await connection.upload(original.path, '/roundtrip/upload.txt');
        expect(
          (await sftp.listdir('/roundtrip')).map((entry) => entry.filename),
          contains('upload.txt'),
        );
        final downloaded = '${temp.path}/downloaded.txt';
        await connection.download('/roundtrip/upload.txt', downloaded);
        expect(
          await File(downloaded).readAsString(),
          await original.readAsString(),
        );
        await sftp.rename('/roundtrip/upload.txt', '/roundtrip/renamed.txt');
        await sftp.remove('/roundtrip/renamed.txt');
        await sftp.rmdir('/roundtrip');
        await connection.close();
        expect(connection.isClosed, isTrue);
      },
    );
  });
}
