# SSH Mate compatibility patch

This directory vendors xterm.dart 4.0.0 from the Dart package cache. Its original MIT license and copyright are preserved in LICENSE.

The only source change is in `lib/src/ui/custom_text_edit.dart`: pass `View.of(context).viewId` to `TextInputConfiguration`. Current Flutter Windows rejects a text input client without a view ID. Keeping the patch in this repository makes builds reproducible without modifying a developer's global package cache. Preserve IME/composition support when updating this dependency.
