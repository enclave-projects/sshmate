// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'desktop_test_fonts.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshmate/data/vault_repository.dart';
import 'package:sshmate/domain/models.dart';
import 'package:sshmate/ui/theme.dart';
import 'package:sshmate/ui/workspace_view.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> persisted(WidgetTester tester, bool Function() ready) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pumpAndSettle();
  expect(ready(), isTrue);
}

void main() {
  testWidgets(
    'Organize hosts, credentials, snippets, filters and smaller windows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadDesktopFonts(tester);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sshmate-ui-'),
      ))!;
      final repository = (await tester.runAsync(
        () async => VaultRepository(directory: directory),
      ))!;
      addTearDown(() async {
        repository.lock();
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() => repository.create('test workspace password'));
      var locked = false;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RepaintBoundary(
            key: boundary,
            child: WorkspaceView(
              repository: repository,
              onLock: () => locked = true,
              onTheme: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New host'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save host'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsNWidgets(2));
      await tester.enterText(field('Label'), 'Production API');
      await tester.enterText(field('Address'), '192.0.2.10');
      await tester.enterText(field('Username'), 'deploy');
      await tester.enterText(field('Group'), 'Production');
      await tester.enterText(field('Tags (comma separated)'), 'api, linux');
      await tester.tap(find.text('Save host'));
      await persisted(tester, () => repository.workspace.hosts.length == 1);
      expect(find.text('Production API'), findsOneWidget);
      expect(find.text('#api  #linux'), findsOneWidget);
      await tester.tap(find.byTooltip('Favorite'));
      await persisted(tester, () => repository.workspace.hosts.single.favorite);
      await tester.enterText(find.byType(TextField).first, 'not-a-host');
      await tester.pumpAndSettle();
      expect(find.text('No matching hosts'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Production API'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'linux');
      await tester.pumpAndSettle();
      expect(find.text('Production API'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Host actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Label'), 'Production Gateway');
      await tester.tap(find.text('Save host'));
      await persisted(
        tester,
        () => repository.workspace.hosts.single.label == 'Production Gateway',
      );
      expect(repository.workspace.hosts.single.favorite, isTrue);
      await tester.tap(find.byTooltip('Keychain'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New identity'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Label'), 'Deployment credentials');
      await tester.enterText(field('Username (optional)'), 'deploy');
      await tester.enterText(field('SSH password'), 'dummy secret only');
      await tester.tap(find.text('Save'));
      await persisted(
        tester,
        () => repository.workspace.identities.length == 1,
      );
      expect(find.text('Deployment credentials'), findsOneWidget);
      expect(find.text('dummy secret only'), findsNothing);
      await tester.tap(find.byTooltip('Snippets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New snippet'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Label'), 'Check disk usage');
      await tester.enterText(field('Command'), 'df -h');
      await tester.tap(find.text('Save'));
      await persisted(tester, () => repository.workspace.snippets.length == 1);
      expect(find.text('df -h'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Send to terminal'),
            )
            .onPressed,
        isNull,
      );
      await tester.runAsync(
        () => repository.save(
          repository.workspace.copyWith(
            hosts: [
              repository.workspace.hosts.single,
              Host(
                id: 'fixture-2',
                label: 'Staging dashboard',
                address: '198.51.100.20',
                username: 'ubuntu',
                group: 'Staging',
                tags: ['web', 'staging'],
              ),
              Host(
                id: 'fixture-3',
                label: 'Development lab',
                address: '203.0.113.30',
                username: 'developer',
                group: 'Development',
                tags: ['sandbox'],
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('Hosts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('Production Gateway'), findsOneWidget);
      expect(find.text('Staging dashboard'), findsNothing);
      await tester.tap(find.text('All hosts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staging'));
      await tester.pumpAndSettle();
      expect(find.text('Staging dashboard'), findsOneWidget);
      expect(find.text('Production Gateway'), findsNothing);
      await tester.tap(find.text('All hosts'));
      await tester.pumpAndSettle();
      if (Platform.isWindows) {
        await tester.pump();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(
          () => render.toImage(pixelRatio: 1),
        ))!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(() async {
          await Directory('test/artifacts').create(recursive: true);
          await File('test/artifacts/workspace.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
        image.dispose();
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(light: true),
          home: RepaintBoundary(
            key: boundary,
            child: WorkspaceView(
              repository: repository,
              onLock: () => locked = true,
              onTheme: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.isWindows) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(
          () => render.toImage(pixelRatio: 1),
        ))!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(
          () =>
              File('test/artifacts/workspace-light.png')
                  .writeAsBytes(bytes!.buffer.asUint8List()),
        );
        image.dispose();
      }
      await tester.binding.setSurfaceSize(const Size(800, 650));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Export encrypted backup'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final section in [
        'Snippets',
        'Port forwarding',
        'Keychain',
        'Known hosts',
        'History',
        'SFTP',
        'Hosts',
      ]) {
        await tester.tap(find.byTooltip(section));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section);
      }
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock workspace'));
      await tester.pump();
      expect(locked, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
