import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Nhãn phân mục (Section Label) chuẩn cho các Tab trong Quick Settings Panel.
class SectionLabel extends StatelessWidget {
  final String label;
  final bool isFirst;

  const SectionLabel({super.key, required this.label, this.isFirst = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: 8, top: isFirst ? 8 : 32),
      child: Text(
        label,
        style: AppTheme.title.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
