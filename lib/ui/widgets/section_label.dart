import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Nhãn phân mục (Section Label) chuẩn cho các Tab trong Quick Settings Panel.
class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
