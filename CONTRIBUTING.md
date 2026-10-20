# Contributing to SSH Mate

Thanks for helping improve SSH Mate. Contributions should keep the app usable offline, preserve protocol interoperability and avoid introducing a required vendor account or service.

## Development setup

Use Flutter/Dart 3.13.4 or compatible and the Visual Studio C++ desktop workload. On Windows:

```powershell
flutter pub get
python -m pip install -r test/fixtures/requirements.txt
flutter run -d windows
```

The Python package runs only the temporary loopback SSH/SFTP fixture used by tests. Never use personal or production server credentials in test data.

## Before submitting

Run the checks relevant to your change:

```powershell
flutter analyze
flutter test
flutter test integration_test/ssh_mate_e2e_test.dart -d windows --dart-define=SSH_MATE_REPO=$PWD
flutter build windows --release
```

Include behavior tests when connection, vault, import or file-transfer behavior changes. For visible UI changes, include a screenshot and check both themes and a compact window. Do not commit `.dart_tool/`, `build/`, `.pub/`, vault contents, credentials or generated user data.

## Code and security

Follow Dart formatting and the conventions in [AGENTS.md](AGENTS.md). Keep domain/data code separate from Flutter presentation. SSH host keys must remain explicitly verified; OpenSSH imports must stay inert; secret values must never appear in logs, screenshots or error messages.

Keep the vendored xterm.dart MIT license and the patch notes in `third_party/xterm`. When updating it, preserve the Flutter view-ID text-input patch and run terminal input regression checks. Do not edit generated Windows files under `windows/flutter/` by hand.

Report suspected vulnerabilities privately to the maintainer with a reproduction and redacted evidence. Do not open a public issue containing keys, passwords or decrypted vault data.

## Pull requests

Use a short imperative title, for example `Improve SFTP transfer feedback`. Describe the user-visible behavior, explain the reason for the change, link a related issue when one exists, and list checks you ran with their results. Keep each pull request focused and disclose any security or compatibility tradeoffs.
