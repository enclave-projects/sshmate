# Repository Guidelines

## Project Structure

This repository is a Flutter application. Dart code is in `lib/`: `domain/` holds models, `data/` holds vault and SSH services, and `ui/` holds views and controllers. `lib/main.dart` is the entry point. Unit/widget tests and the disposable SSH fixture are in `test/`; native Windows acceptance tests are in `integration_test/`. The `windows/` directory contains the Windows desktop runner and generated Flutter integration files; keep platform-specific changes there. Flutter and Dart dependencies and SDK constraints are declared in `pubspec.yaml`, with the lockfile in `pubspec.lock`. No separate assets directory is currently configured.

## Build, Test, and Development

- `flutter pub get` resolves the dependencies declared by the package.
- `flutter run -d windows` launches the desktop app on Windows; omit `-d windows` to select an available device.
- `flutter analyze` runs the Dart analyzer using the repository's `flutter_lints` configuration.
- `flutter test` runs unit/widget tests and loopback protocol checks. Install their fixture dependency with `python -m pip install -r test/fixtures/requirements.txt`.
- `flutter build windows` creates a Windows release build (requires the Flutter Windows toolchain).

## Coding Style

Follow standard Dart formatting: two-space indentation, trailing commas for multiline argument and collection lists, and `dart format` formatting. Use `UpperCamelCase` for types, `lowerCamelCase` for members and variables, and `snake_case.dart` for file names. Keep widgets and application logic in `lib/`; add focused files as the app grows rather than expanding the entry point indefinitely. Preserve the enabled `flutter_lints` rules in `analysis_options.yaml` and avoid editing generated files under `windows/flutter/` directly.

## Testing Guidelines

Use `flutter_test` for widget and unit tests. Name test files with a `_test.dart` suffix (for example, `test/widget_test.dart`) and give each test a behavior-focused description. Run `flutter test` and `flutter analyze` before submitting changes. Add or update tests when behavior changes; no coverage threshold is currently configured.

## Commits and Pull Requests

Git history is unavailable in this checkout, so no established commit convention could be verified. Use short, imperative commit subjects that describe one change (for example, `Add SSH connection form`). Pull requests should explain the user-visible change, note relevant validation commands and results, link related issues when applicable, and include screenshots for visual UI changes.

## Configuration and Generated Files

Do not commit local build output or tool state such as `.dart_tool/`, `build/`, or `.pub/`. Update `pubspec.lock` when dependency resolution changes. Keep secrets and machine-specific configuration out of source control. New application code uses GPL-3.0-only headers. Never execute imported SSH configuration directives or bypass host fingerprint verification.
