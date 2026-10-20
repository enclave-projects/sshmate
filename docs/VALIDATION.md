<!-- Copyright 2026 SSH Mate contributors. SPDX-License-Identifier: GPL-3.0-only -->
# Validation record

Verified on Windows on 20 October 2026 with Flutter 3.47.5 and Dart 3.13.4.

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 19 passing tests |
| Native Windows integration test | 1 passing acceptance scenario |
| `flutter build windows --release` | Built `sshmate.exe` and companion runtime files |

The tests cover encrypted vault persistence, wrong passwords, tampering, backup restore/import, password rotation, concurrent updates and lock cancellation; inert OpenSSH metadata parsing; and UI creation/editing, search, favorites, filtering, identity/snippet editing and resizing. The generated [workspace preview](../test/artifacts/workspace.png) contains only disposable fixtures.

Seven protocol tests use a temporary Python Paramiko SSH/SFTP server on loopback. They exercise password and ephemeral private-key authentication, rejection of a server fingerprint, failed authentication, cancellation during trust, PTY Unicode/resize, independent session cleanup, streamed SFTP roundtrips and file operations, and a local tunnel through SSH to a separate loopback echo server.

The native acceptance command is:

```powershell
flutter test integration_test/ssh_mate_e2e_test.dart -d windows --dart-define=SSH_MATE_REPO=$PWD
```

It unlocks an isolated persisted vault, connects by clicking a seeded host, accepts the displayed fingerprint, checks actual xterm echo, opens the remote SFTP listing, closes the tab and locks the workspace. Production servers, production credentials and live Termius behavior were not used. Native file chooser transfer interaction, broad server compatibility, failure recovery, cryptographic review and exact reference-app visual parity remain unverified. Native upload/download correctness is supported by service roundtrip tests, not a file chooser automation claim.

## Terminal input regression (0.1.1)

The vendored MIT-licensed xterm 4.0.0 now supplies the containing Flutter view ID when attaching its text input client. The focused regression asserts that configuration and exercises IME text, Enter, Ctrl+C, arrow keys and Backspace. SSH terminal focus is explicitly owned per pane, restored after connection and SFTP/workspace switches, and excluded from hidden tabs.

The native Windows acceptance test now exercises the text input path instead of calling `TerminalPaneState.send` directly. It first allows the real Windows input client attachment and checks for exceptions, then uses Flutter's IME event simulator plus Enter key events to drive real SSH echo roundtrips. It verifies focus after returning from SFTP, hiding the terminal and returning to its tab. This does not automate physical OS keyboard input or every IME. All 19 tests and the updated native scenario pass; static analysis is clean.

## Workbench UI verification (0.2.0)

The existing 19-test suite passes. The updated workspace flow additionally exercises filter recovery, all compact navigation destinations and light appearance. Dark/light fixture renders were inspected at 1280 Ã— 900. The native Windows SSH typing and SFTP scenario passed after the terminal toolbar changes. Component tests cover keyboard activation, reduced motion and semantic error feedback. Full accessibility conformance and every Windows scaling setting have not been audited.

