// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

class VaultException implements Exception {
  const VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A portable, authenticated encrypted workspace; never writes cleartext.
class VaultRepository {
  VaultRepository({this._directory});
  Directory? _directory;
  SecretKey? _key;
  List<int>? _salt;
  Workspace? _workspace;
  int _generation = 0;
  Future<void> _writes = Future.value();
  static const _iterations = 600000;
  static const _aad = 'ssh-mate-vault:1:pbkdf2-sha256:600000:aes256-gcm';
  final _cipher = AesGcm.with256bits();
  bool get isUnlocked => _key != null;
  Workspace get workspace =>
      _workspace ?? (throw const VaultException('Vault is locked.'));
  Future<File> get _file async {
    _directory ??= Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}vault',
    );
    return File(
      '${_directory!.path}${Platform.pathSeparator}workspace.sshmate',
    );
  }

  Future<bool> exists() async => (await _file).exists();
  List<int> _random(int count) {
    final random = Random.secure();
    return List.generate(count, (_) => random.nextInt(256));
  }

  Future<SecretKey> _derive(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  Future<void> create(String password) async {
    if (password.length < 12) {
      throw const VaultException(
        'Use a master password of at least 12 characters.',
      );
    }
    if (await exists()) {
      throw const VaultException('A vault already exists. Unlock it instead.');
    }
    final generation = ++_generation;
    final salt = _random(32);
    final key = await _derive(password, salt);
    if (generation != _generation) {
      throw const VaultException('Vault operation cancelled.');
    }
    _salt = salt;
    _key = key;
    _workspace = Workspace();
    try {
      await save(workspace);
    } catch (_) {
      if (generation == _generation) lock();
      rethrow;
    }
  }

  Future<({Workspace workspace, SecretKey key, List<int> salt})> _decode(
    File file,
    String password,
  ) async {
    try {
      if (await file.length() > 32 * 1024 * 1024) throw const FormatException();
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (j['format'] != 'ssh-mate-vault' ||
          j['version'] != 1 ||
          j['iterations'] != _iterations) {
        throw const FormatException();
      }
      final salt = base64Decode(j['salt']);
      final nonce = base64Decode(j['nonce']);
      final mac = base64Decode(j['mac']);
      if (salt.length != 32 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException();
      }
      final key = await _derive(password, salt);
      final clear = await _cipher.decrypt(
        SecretBox(base64Decode(j['ciphertext']), nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      return (
        workspace: Workspace.fromJson(jsonDecode(utf8.decode(clear))),
        key: key,
        salt: salt,
      );
    } catch (_) {
      throw const VaultException(
        'Unable to unlock: incorrect password, damaged file, or unsupported vault.',
      );
    }
  }

  Future<void> unlock(String password) async {
    lock();
    final generation = _generation;
    final decoded = await _decode(await _file, password);
    if (generation != _generation) {
      throw const VaultException('Vault operation cancelled.');
    }
    _key = decoded.key;
    _salt = decoded.salt;
    _workspace = decoded.workspace;
  }

  /// Restores a portable vault into a new installation without creating one.
  Future<void> restoreFrom(File source, String password) async {
    if (isUnlocked || await exists()) {
      throw const VaultException('Restore requires an empty, locked vault.');
    }
    final generation = ++_generation;
    final decoded = await _decode(source, password);
    final destinationExists = await exists();
    if (generation != _generation || destinationExists) {
      throw const VaultException('Vault operation cancelled.');
    }
    _key = decoded.key;
    _salt = decoded.salt;
    _workspace = decoded.workspace;
    try {
      await save(decoded.workspace);
    } catch (_) {
      if (generation == _generation) lock();
      rethrow;
    }
  }

  void lock() {
    _generation++;
    _key = null;
    _salt = null;
    _workspace = null;
  }

  Future<void> save(Workspace value) {
    final key = _key;
    final salt = _salt;
    final generation = _generation;
    if (key == null || salt == null) {
      return Future.error(const VaultException('Vault is locked.'));
    }
    final operation = _writes.then((_) async {
      if (generation != _generation) {
        throw const VaultException('Vault is locked.');
      }
      await _persist(value, key, salt, generation);
      if (generation == _generation) _workspace = value;
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _persist(
    Workspace value,
    SecretKey key,
    List<int> salt,
    int generation,
  ) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(value.toJson())),
      secretKey: key,
      nonce: _random(12),
      aad: utf8.encode(_aad),
    );
    final contents = jsonEncode({
      'format': 'ssh-mate-vault',
      'version': 1,
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
    final file = await _file;
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${base64UrlEncode(_random(12))}.tmp');
    try {
      await temporary.writeAsString(contents, flush: true);
      if (generation != _generation) {
        throw const VaultException('Vault is locked.');
      }
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Reencrypts atomically with a fresh salt after authenticating the old password.
  Future<void> changePassword(String oldPassword, String newPassword) {
    if (!isUnlocked) {
      return Future.error(const VaultException('Vault is locked.'));
    }
    if (newPassword.length < 12) {
      return Future.error(
        const VaultException(
          'Use a master password of at least 12 characters.',
        ),
      );
    }
    final generation = _generation;
    final operation = _writes.then((_) async {
      if (generation != _generation) {
        throw const VaultException('Vault is locked.');
      }
      await _decode(await _file, oldPassword);
      final salt = _random(32);
      final key = await _derive(newPassword, salt);
      if (generation != _generation) {
        throw const VaultException('Vault is locked.');
      }
      final value = workspace;
      await _persist(value, key, salt, generation);
      if (generation == _generation) {
        _key = key;
        _salt = salt;
        _generation++;
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  /// Copies the encrypted envelope, preserving its master password.
  Future<Uint8List> exportBytes() async {
    if (!isUnlocked) {
      throw const VaultException('Unlock the vault before exporting.');
    }
    final generation = _generation;
    await _writes;
    final bytes = await (await _file).readAsBytes();
    if (generation != _generation) {
      throw const VaultException('Vault is locked.');
    }
    return bytes;
  }

  /// Copies the encrypted envelope, preserving its master password.
  Future<void> exportTo(File destination) async {
    if (!isUnlocked) {
      throw const VaultException('Unlock the vault before exporting.');
    }
    await _writes;
    final source = await _file;
    if (source.absolute.path == destination.absolute.path) {
      throw const VaultException('Choose a different export destination.');
    }
    await source.copy(destination.path);
  }

  /// Decrypts a portable vault and saves it under this vault's existing key.
  Future<void> importFrom(File source, String password) async {
    if (!isUnlocked) {
      throw const VaultException(
        'Unlock the destination vault before importing.',
      );
    }
    final generation = _generation;
    final decoded = await _decode(source, password);
    if (generation != _generation) {
      throw const VaultException('Vault is locked.');
    }
    await save(decoded.workspace);
  }
}
