<!-- Copyright 2026 SSH Mate contributors. SPDX-License-Identifier: GPL-3.0-only -->
# SSH Mate implementation and parity plan

SSH Mate is an original GNU GPLv3 Flutter Windows application. This checklist tracks a bounded first implementation and outstanding work; it does not assert that every Termius feature has been discovered or reproduced. The static reference evidence is recorded in [RESEARCH.md](RESEARCH.md).

## Implemented foundations

The following capabilities have source implementations. Network interoperability and Windows interaction require the validation described below.

- Hosts with labels, addresses, ports, usernames, flat group names, tags, notes and favorites.
- Reusable identities with password or pasted private key and optional passphrase.
- Search, group filtering and original dark desktop navigation.
- Independent SSH connections, xterm terminal sessions and terminal tabs.
- SFTP browsing, streamed upload/download, rename/delete, and directory creation/removal.
- Saved local forwarding rules with loopback listeners.
- Saved command snippets and connection history.
- Master password protected local workspace; separate vault folders, password rotation, portable encrypted backup and restore.
- Trusted host fingerprints and rejection of changed keys.
- Per-connection cleanup and explicit vault locking.
- Previewed import of literal OpenSSH configuration metadata.

## Feature parity checklist

| Area | Current scope | Outstanding work |
| --- | --- | --- |
| Hosts/groups | Flat grouping, tags, search, favorites, notes | Nested groups, inherited credentials/configuration, multi-selection, bulk edits, IPv4/IPv6 preferences |
| Authentication | Password and PEM identity | SSH agent, hardware/FIDO2, certificates, keyboard interactive/MFA, key generation and rotation |
| SSH terminal | Tabbed xterm shell | Split panes, broadcast, workspace templates, reconnection policy, local PTY, configurable shortcuts |
| Connectivity | Direct SSH | Jump host chains, proxies, Telnet, Serial, Mosh |
| SFTP | Browse, upload/download, rename/delete, mkdir/rmdir | Dual panes, recursive transfers, resume, queue/cancel, permission editor, Open with associations |
| Forwarding | Local loopback tunnels | Remote forwards, dynamic SOCKS, profiles and automatic startup |
| Snippets | Store/edit commands | Parameter templates, folders, multi-host execution, optional local AI provider |
| History/logging | Bounded connection history | Opt-in session recording, redaction, retention and searchable command history |
| Vaults | One open vault at a time; separate folders, per-vault settings, password changes | Concurrent writer coordination and stronger process boundaries |
| Portability | Encrypted SSH Mate envelope; partial literal OpenSSH import with preview | Complete SSH config semantics, CSV imports, migration tools, versioned interoperable format documentation |
| Collaboration | No account or backend required | Optional user-controlled encrypted sync, key exchange, access revocation, multiplayer |
| Accessibility | Flutter desktop widgets | Full keyboard audit, screen reader labels, contrast and scaling review |
| Settings | Initial workspace settings | Theme palettes, fonts, terminal behavior and comprehensive shortcut editor |

## Delivery order and acceptance

1. Harden the local workflow: test vault authentication and corruption handling, changed host keys, import replacement, locking and session cleanup. Build and analyze on Windows.
2. Validate SSH/SFTP/forwarding against disposable local servers with password and key authentication. Exercise resize, Unicode, disconnects, failed authentication and transfer failures. No production credentials are needed.
3. Add missing local productivity capabilities, starting with recursive transfers, nested groups, jump hosts, split panes and config import. Add behavior tests per feature.
4. Review separate vault folder isolation and password rotation, add concurrent writer protection, and obtain cryptographic review.
5. Design optional synchronization only after documenting participants, device identity, encryption endpoints, revocation and recovery. Keep the standalone app usable without a vendor account.

Do not label a checklist item complete from a button or static label alone. Record test commands and results separately from successful real-server scenarios. Exhausting the current checklist does not prove complete Termius feature coverage.

## Recorded validation

Seven disposable loopback transport tests passed, including password/private-key authentication, SFTP operations, local forwarding, host-key rejection, failed authentication, cancellation during pending trust, and independent connection cleanup. The native Windows acceptance test also passed through unlocking a persisted isolated vault, selecting its seeded host, first-use fingerprint trust, SSH terminal input/output, SFTP rendering, tab closure and locking. These controlled scenarios do not establish complete interoperability or Termius parity.
