// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/vault_repository.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'SSH Mate',
    ], await rootBundle.loadString('LICENSE'));
  });
  runApp(SshMateApp(repository: VaultRepository()));
}
