import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../widgets/cap_surface.dart';

/// Console-style gamepad hint bar pinned to the bottom of the Quick Panel.
///
/// Uses the same recessed surface as the tab bar and the same [CapSurface]
/// material as the LB / RB shoulder keys, so both chrome bars read as one
/// piece of hardware.
class PanelFooter extends StatelessWidget {
  const PanelFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        gradient: AppTheme.tabBarGradient,
        border: Border(top: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildHintBadge("X", "Thông tin", AppTheme.info),
          const SizedBox(width: 16),
          _buildHintBadge("A", "Chọn", AppTheme.success),
          const SizedBox(width: 16),
          _buildHintBadge("B", "Đóng", AppTheme.danger),
        ],
      ),
    );
  }

  /// Face button cap plus its caption. The accent only tints the rim and the
  /// glyph; the cap fill stays the shared metal gradient.
  Widget _buildHintBadge(String keyText, String label, Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CapSurface(
          shape: CapShape.circle,
          width: AppTheme.scaledHalf(20),
          height: AppTheme.scaledHalf(20),
          accent: accent,
          child: Center(
            child: Text(
              keyText,
              style: AppTheme.footer.copyWith(
                fontSize: AppTheme.scaled(12),
                letterSpacing: 0,
                color: accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTheme.footer.copyWith(fontWeight: FontWeight.normal),
        ),
      ],
    );
  }
}
