// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:sshmate/data/ssh_config_importer.dart';

void main() {
  test('imports aliases, quoted metadata and literal connection values', () {
    final result = SshConfigImporter.parse('''
Host production prod
  HostName=10.0.0.2 # trusted comment
  User = deploy
  Port 2222
  IdentityFile "C:\\Users\\me\\my key"
Host ipv6
  HostName 2001:db8::1
''');
    expect(result.hosts.map((host) => host.label), [
      'production',
      'prod',
      'ipv6',
    ]);
    expect(result.hosts.first.address, '10.0.0.2');
    expect(result.hosts.first.username, 'deploy');
    expect(result.hosts.first.port, 2222);
    expect(result.hosts.first.notes, contains('my key'));
    expect(result.hosts.first.identityId, isNull);
    expect(result.hosts.last.address, '2001:db8::1');
    expect(result.warnings.single, contains('not read'));
  });
  test(
    'skips patterns, includes, commands and Match without executing them',
    () {
      final result = SshConfigImporter.parse(r'''
Include ~/.ssh/other
Host * !private *.internal
  User should-not-be-inherited
Host literal
  ProxyCommand powershell Remove-Item
  ProxyJump jump
  HostName localhost
Match exec "anything"
  HostName should-not-override
Host safe
  Port 22
''');
      expect(result.hosts.map((host) => host.label), ['literal', 'safe']);
      expect(result.hosts.first.username, '');
      expect(result.hosts.first.address, 'localhost');
      expect(result.warnings, hasLength(7));
    },
  );
  test('duplicate aliases and invalid ports are deterministic', () {
    const config = '''
Host same
 HostName first
Host SAME
 HostName second
Host bad
 Port 70000
Host variable
 HostName %h.example
Host valid
 HostName "unterminated
 HostName valid.example
''';
    final first = SshConfigImporter.parse(config);
    final second = SshConfigImporter.parse(config);
    expect(first.hosts.map((host) => host.label), ['same', 'valid']);
    expect(first.hosts.first.address, 'first');
    expect(
      first.hosts.map((host) => host.id),
      second.hosts.map((host) => host.id),
    );
    expect(first.warnings, hasLength(4));
  });
}
