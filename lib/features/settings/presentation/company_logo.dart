import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';

/// The company's logo in a circle, or its initials when it has none or the image
/// cannot be loaded (the server's address for it may not be reachable).
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({super.key, required this.name, this.url, this.size = 56});

  final String name;
  final String? url;
  final double size;

  /// `Ownit2Buildit Zimbabwe` → `OZ`; one word gives its first two letters.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'BP';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: AppType.bodyStrong.copyWith(
          color: c.primaryText,
          fontSize: size * 0.34,
        ),
      ),
    );
    final address = url;
    return Semantics(
      label: 'Company logo',
      image: true,
      excludeSemantics: true,
      child: address == null
          ? fallback
          : ClipOval(
              // A logo is often dark on transparent: it sits on white so it
              // reads in the dark theme too.
              child: ColoredBox(
                color: Colors.white,
                child: Image.network(
                  address,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : fallback,
                ),
              ),
            ),
    );
  }
}
