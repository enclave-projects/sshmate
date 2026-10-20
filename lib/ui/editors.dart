// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/models.dart';

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class FieldSpec {
  const FieldSpec(
    this.label, {
    this.value = '',
    this.secret = false,
    this.lines = 1,
    this.required = false,
    this.port = false,
  });
  final String label, value;
  final bool secret, required, port;
  final int lines;
}

Future<List<String>?> editFields(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  String action = 'Save',
  String? description,
  bool importKey = false,
}) async {
  final values = fields
      .map((f) => TextEditingController(text: f.value))
      .toList();
  final form = GlobalKey<FormState>();
  final revealed = <int>{};
  final route = DialogRoute<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 470,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(description),
                    ),
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: values[i],
                        autofocus: i == 0,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        obscureText: fields[i].secret && !revealed.contains(i),
                        maxLines: fields[i].lines,
                        decoration: InputDecoration(
                          labelText: fields[i].label,
                          suffixIcon: fields[i].secret
                              ? IconButton(
                                  tooltip: revealed.contains(i)
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: () => update(() {
                                    if (!revealed.add(i)) revealed.remove(i);
                                  }),
                                  icon: Icon(
                                    revealed.contains(i)
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                )
                              : null,
                        ),
                        validator: (value) {
                          if (fields[i].required &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Required';
                          }
                          if (fields[i].port &&
                              ((int.tryParse(value ?? '') ?? 0) < 1 ||
                                  (int.tryParse(value ?? '') ?? 0) > 65535)) {
                            return 'Use a port from 1 to 65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  if (importKey)
                    TextButton.icon(
                      onPressed: () async {
                        final file = await FilePicker.pickFile(
                          dialogTitle: 'Import your private key',
                        );
                        if (file?.path != null) {
                          try {
                            final source = File(file!.path!);
                            if (await source.length() > 1024 * 1024) {
                              throw const FormatException(
                                'Private key exceeds 1 MiB.',
                              );
                            }
                            final text = await source.readAsString();
                            if (context.mounted) values[2].text = text;
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not read private key: $error',
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import private key from file'),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, values.map((v) => v.text).toList());
              }
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  for (final value in values) {
    value.dispose();
  }
  return result;
}

Future<Host?> editHost(
  BuildContext context, {
  Host? host,
  required List<Identity> identities,
}) async {
  final fields = [
    FieldSpec('Label', value: host?.label ?? '', required: true),
    FieldSpec('Address', value: host?.address ?? '', required: true),
    FieldSpec('Port', value: '${host?.port ?? 22}', port: true),
    FieldSpec('Username', value: host?.username ?? 'root', required: true),
    FieldSpec('Group', value: host?.group ?? ''),
    FieldSpec('Tags (comma separated)', value: host?.tags.join(', ') ?? ''),
    FieldSpec('Notes', value: host?.notes ?? '', lines: 3),
  ];
  final controllers = fields
      .map((f) => TextEditingController(text: f.value))
      .toList();
  String selected = identities.any((i) => i.id == host?.identityId)
      ? host!.identityId!
      : '';
  final form = GlobalKey<FormState>();
  final route = DialogRoute<Host>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(host == null ? 'New host' : 'Edit host'),
        content: SizedBox(
          width: 490,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: controllers[i],
                        autofocus: i == 0,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: InputDecoration(labelText: fields[i].label),
                        maxLines: fields[i].lines,
                        validator: (value) {
                          if (fields[i].required &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Required';
                          }
                          if (i == 1 &&
                              (value!.contains(RegExp(r'\s')) ||
                                  value.startsWith('-') ||
                                  value.contains('://'))) {
                            return 'Enter a hostname or IP address';
                          }
                          if (fields[i].port &&
                              ((int.tryParse(value ?? '') ?? 0) < 1 ||
                                  (int.tryParse(value ?? '') ?? 0) > 65535)) {
                            return 'Use a port from 1 to 65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Identity'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Ask for password on connection'),
                      ),
                      for (final identity in identities)
                        DropdownMenuItem(
                          value: identity.id,
                          child: Text(identity.label),
                        ),
                    ],
                    onChanged: (value) => update(() => selected = value ?? ''),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final v = controllers.map((c) => c.text.trim()).toList();
              Navigator.pop(
                context,
                Host(
                  id: host?.id ?? newId(),
                  label: v[0],
                  address: v[1],
                  port: int.parse(v[2]),
                  username: v[3],
                  group: v[4],
                  tags: v[5]
                      .split(',')
                      .map((t) => t.trim())
                      .where((t) => t.isNotEmpty)
                      .toList(),
                  notes: v[6],
                  identityId: selected.isEmpty ? null : selected,
                  favorite: host?.favorite ?? false,
                ),
              );
            },
            child: const Text('Save host'),
          ),
        ],
      ),
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  for (final c in controllers) {
    c.dispose();
  }
  return result;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String text, {
  String action = 'Delete',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: action == 'Delete'
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
