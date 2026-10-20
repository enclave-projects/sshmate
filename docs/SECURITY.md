<!-- Copyright 2026 SSH Mate contributors. SPDX-License-Identifier: GPL-3.0-only -->
# Security model

## Local data and portable backups

`VaultRepository` stores the workspace as an authenticated encrypted JSON envelope in the application support directory under `vault/workspace.sshmate`. Hosts, private keys, passwords, settings, trusted fingerprints and history are inside the ciphertext. The envelope exposes format/version, salt, nonce, authentication tag and ciphertext length.

The implementation uses AES-256-GCM with a fresh random 96-bit nonce per save, a random 256-bit salt per vault, and PBKDF2-HMAC-SHA256 with 600,000 iterations to derive a 256-bit key. Fixed additional authenticated data binds the current format and algorithms. Creation requires a master password of at least 12 characters. Password changes authenticate the current password and derive a new key with a fresh salt; existing exported backups keep their old password. Use a long unique password; there is no password recovery service.

Exports copy the encrypted envelope and retain its password. Imports decrypt a selected SSH Mate envelope and replace the destination workspace under the destination key. Imported credentials and trusted host entries therefore become authoritative; inspect the source before restoring. Keep a backup before replacement. This is not a Termius vault importer.

Encrypted local storage is encryption at rest. It is not a reviewed end-to-end synchronization protocol. There is currently no sync server, account, sharing key exchange, device enrollment or recovery protocol. Separate local vault folders can be selected at the lock screen; only one is open at a time.

## Connections and isolation

SSH transport and SFTP are provided by `dartssh2`. Each connection owns its client, authentication context and channels. Local forwards bind only IPv4 loopback. A remote server can see terminal commands, transferred plaintext and forwarding destinations after SSH decryption.

The UI requests trust for new SSH host fingerprints; previously trusted keys must match. Verify first-use fingerprints through an independent trusted channel. Removing the local trust record permits a new first-use decision.

Vault locking closes active sessions through the UI and discards accessible key/workspace references. Dart garbage collection cannot guarantee prompt erasure of keys, passwords, clipboard contents or terminal buffers. This is operation lifecycle isolation within one process, not a Windows sandbox or separate security boundary per operation.

## Limits and operational guidance

- An unlocked application or compromised Windows account can access decrypted data. Protect the device and lock the vault when leaving it.
- There is no automatic idle lock or OS credential integration yet. Optional lock when hidden closes sessions when the app is minimized or hidden.
- SFTP download destinations and uploaded source files are ordinary plaintext files. Terminal output may contain secrets.
- Transfers currently write directly to destinations; interrupted transfers can leave partial files. Avoid overwriting the only copy of important data.
- The vault uses serialized encrypted temporary writes and rename. Multiple application processes are not coordinated; use one instance per workspace.
- Offline operation means no vendor service is needed. SSH, SFTP and tunnels still connect to user-selected remote endpoints.
- Independent cryptographic review, crash recovery testing and broader interoperability testing remain required before treating this as a hardened credential manager.

OpenSSH configuration import reads supported literal host metadata, shows a preview, and reports unsupported directives. It does not run commands, expand Include/Match blocks, or automatically read private keys.

Report a suspected vulnerability privately to the project maintainer with affected version, reproduction steps and redacted evidence. Do not publish credentials, private keys or decrypted vault contents in issues.
