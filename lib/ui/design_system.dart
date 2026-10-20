// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import 'theme.dart';

/// A shared interactive surface; focus and hover never move surrounding layout.
class MateSurface extends StatefulWidget {
  const MateSurface({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<MateSurface> createState() => _MateSurfaceState();
}

class _MateSurfaceState extends State<MateSurface> {
  bool hover = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: MateMotion.duration(context),
      decoration: BoxDecoration(
        color: hover || focused
            ? c.surfaceContainerHighest
            : c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused
              ? c.primary
              : hover
              ? c.primary.withValues(alpha: .6)
              : c.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          onHover: (v) => setState(() => hover = v),
          onFocusChange: (v) => setState(() => focused = v),
          child: widget.child,
        ),
      ),
    );
  }
}

class MateNotice extends StatelessWidget {
  const MateNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final color = error ? c.error : c.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: error ? c.error : c.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MateSectionLabel extends StatelessWidget {
  const MateSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
