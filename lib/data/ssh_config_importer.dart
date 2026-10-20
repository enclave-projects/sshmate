// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import '../domain/models.dart';

class SshConfigImportResult {
  SshConfigImportResult({
    required List<Host> hosts,
    required List<String> warnings,
  }) : hosts = List.unmodifiable(hosts),
       warnings = List.unmodifiable(warnings);
  final List<Host> hosts;
  final List<String> warnings;
}

/// Imports literal OpenSSH Host blocks as inert host metadata.
///
/// Never executes directives, expands variables, follows Include, reads keys,
/// or applies wildcard/default/Match blocks. Unsupported behavior is reported.
class SshConfigImporter {
  static SshConfigImportResult parse(String source) {
    final hosts = <Host>[];
    final warnings = <String>[];
    final seenAliases = <String>{};
    var aliases = <String>[];
    var values = <String, String>{};
    var blockLine = 0;
    void finishBlock() {
      for (final alias in aliases) {
        if (!seenAliases.add(alias.toLowerCase())) {
          warnings.add(
            'Line $blockLine: duplicate Host "$alias" ignored; first block wins.',
          );
          continue;
        }
        final address = values['hostname'] ?? alias;
        if (RegExp(r'[\s%$]').hasMatch(address)) {
          warnings.add(
            'Line $blockLine: Host "$alias" has a nonliteral HostName and was skipped.',
          );
          continue;
        }
        final portText = values['port'];
        final port = portText == null ? 22 : int.tryParse(portText);
        if (port == null || port < 1 || port > 65535) {
          warnings.add(
            'Line $blockLine: Host "$alias" has an invalid Port and was skipped.',
          );
          continue;
        }
        final identityFile = values['identityfile'];
        hosts.add(
          Host(
            id: 'ssh-config-${Uri.encodeComponent(alias.toLowerCase())}',
            label: alias,
            address: address,
            port: port,
            username: values['user'] ?? '',
            group: 'Imported',
            notes: identityFile == null
                ? ''
                : 'OpenSSH IdentityFile: $identityFile\nMetadata only. Select an identity in SSH Mate to use a key.',
          ),
        );
      }
    }

    final lines = source.split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index++) {
      final lineNumber = index + 1;
      List<String> tokens;
      try {
        tokens = _tokenize(lines[index]);
      } on FormatException {
        warnings.add('Line $lineNumber: unterminated quoted value ignored.');
        continue;
      }
      if (tokens.isEmpty) continue;
      final keyword = tokens.removeAt(0).toLowerCase();
      if (keyword == 'host') {
        finishBlock();
        aliases = [];
        values = {};
        blockLine = lineNumber;
        for (final alias in tokens) {
          if (RegExp(r'[*?!\[\]%$\s]').hasMatch(alias)) {
            warnings.add(
              'Line $lineNumber: wildcard, excluded, or variable Host "$alias" ignored.',
            );
          } else {
            aliases.add(alias);
          }
        }
        if (tokens.isEmpty) {
          warnings.add('Line $lineNumber: empty Host block ignored.');
        }
        continue;
      }
      if (keyword == 'match') {
        finishBlock();
        aliases = [];
        values = {};
        warnings.add(
          'Line $lineNumber: Match conditions are unsupported and ignored.',
        );
        continue;
      }
      if (keyword == 'include' ||
          keyword == 'proxycommand' ||
          keyword == 'proxyjump' ||
          keyword == 'localcommand' ||
          keyword == 'remotecommand') {
        warnings.add(
          'Line $lineNumber: $keyword is unsupported; no files are read and no commands are executed.',
        );
        continue;
      }
      if (aliases.isEmpty) continue;
      if (!const {
        'hostname',
        'user',
        'port',
        'identityfile',
      }.contains(keyword)) {
        warnings.add(
          'Line $lineNumber: unsupported option "$keyword" ignored.',
        );
        continue;
      }
      if (tokens.length != 1) {
        warnings.add(
          'Line $lineNumber: $keyword requires one value and was ignored.',
        );
        continue;
      }
      if (values.containsKey(keyword)) {
        warnings.add(
          'Line $lineNumber: additional $keyword ignored; first value wins.',
        );
        continue;
      }
      values[keyword] = tokens.single;
      if (keyword == 'identityfile') {
        warnings.add(
          'Line $lineNumber: IdentityFile kept as metadata; key contents were not read.',
        );
      }
    }
    finishBlock();
    return SshConfigImportResult(hosts: hosts, warnings: warnings);
  }

  static List<String> _tokenize(String line) {
    final result = <String>[];
    var current = StringBuffer();
    String? quote;
    var hasToken = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '\\' &&
          i + 1 < line.length &&
          (line[i + 1] == '"' ||
              line[i + 1] == "'" ||
              line[i + 1] == ' ' ||
              line[i + 1] == '#')) {
        current.write(line[++i]);
        hasToken = true;
      } else if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
        hasToken = true;
      } else if (char == '"' || char == "'") {
        quote = char;
        hasToken = true;
      } else if (char == '#') {
        break;
      } else if (char.trim().isEmpty || (char == '=' && result.isEmpty)) {
        if (hasToken) {
          result.add(current.toString());
          current = StringBuffer();
          hasToken = false;
        }
      } else if (char == '=' && result.length == 1 && !hasToken) {
        continue;
      } else {
        current.write(char);
        hasToken = true;
      }
    }
    if (quote != null) throw const FormatException('Unterminated quote');
    if (hasToken) result.add(current.toString());
    return result;
  }
}
