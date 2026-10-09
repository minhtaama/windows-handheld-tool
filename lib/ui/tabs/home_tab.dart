import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../hardware/device_info_service.dart';
import '../../services/system_telemetry_service.dart';
import '../widgets/section_label.dart';

/// Tab Trang chủ (Homepage): Hiển thị đồng hồ theo thiết lập Windows, % pin & sạc, và chỉ số phần cứng (CPU, GPU, RAM).
class HomeTab extends StatelessWidget {
  final ScrollController scrollController;
  final int focusedIndex;
  final SystemTelemetryData telemetry;
  final int liveTdp;

  const HomeTab({
    super.key,
    required this.scrollController,
    required this.focusedIndex,
    required this.telemetry,
    required this.liveTdp,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('tab_homepage'),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // 1. Khối Đồng hồ hệ thống & Thiết bị Handheld
        _buildClockHeader(),

        // 2. Khối Trạng thái Pin & Nguồn điện
        const SectionLabel(label: "NGUỒN & PIN"),
        _buildBatteryCard(),

        // 3. Khối Tài nguyên Phần cứng
        const SectionLabel(label: "TÀI NGUYÊN HỆ THỐNG"),
        _buildHardwareGrid(),
      ],
    );
  }

  /// Khối hiển thị Đồng hồ lớn chuẩn theo định dạng Windows và Tên thiết bị
  Widget _buildClockHeader() {
    final device = DeviceInfoService.currentDevice;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: focusedIndex == 0 ? AppTheme.primary : AppTheme.cardBorder,
          width: focusedIndex == 0 ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Đồng hồ thời gian thực từ Windows Settings
                Text(
                  telemetry.timeString,
                  style: TextStyle(
                    fontSize: AppTheme.scaled(28),
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: AppTheme.scaled(13),
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      telemetry.dateString,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Huy hiệu định danh thiết bị
                Icon(
                  device.isHandheld
                      ? Icons.videogame_asset_rounded
                      : Icons.computer_rounded,
                  size: AppTheme.scaled(23),
                  color: AppTheme.accent,
                ),
                const SizedBox(height: 6),
                Text(
                  device.displayName,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppTheme.scaled(11),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thẻ trạng thái Pin & Tình trạng sạc
  Widget _buildBatteryCard() {
    final bool hasBattery = telemetry.hasBattery;
    final int percent = telemetry.batteryPercent ?? 100;
    final bool isCharging = telemetry.isCharging;
    final bool isAcOnline = telemetry.isAcOnline;

    // Xác định icon pin phù hợp
    IconData batteryIcon;
    Color statusColor;
    String statusDesc;

    if (!hasBattery) {
      batteryIcon = Icons.power_rounded;
      statusColor = AppTheme.info;
      statusDesc = isAcOnline
          ? "Nguồn AC trực tiếp (Không pin)"
          : "Không phát hiện pin";
    } else if (isCharging) {
      batteryIcon = Icons.battery_charging_full_rounded;
      statusColor = AppTheme.success;
      statusDesc = percent >= 100
          ? "Đã sạc đầy (Nguồn AC)"
          : "Đang sạc nguồn AC";
    } else {
      if (percent > 80) {
        batteryIcon = Icons.battery_full_rounded;
        statusColor = AppTheme.success;
      } else if (percent > 40) {
        batteryIcon = Icons.battery_5_bar_rounded;
        statusColor = AppTheme.info;
      } else if (percent > 20) {
        batteryIcon = Icons.battery_3_bar_rounded;
        statusColor = AppTheme.warning;
      } else {
        batteryIcon = Icons.battery_alert_rounded;
        statusColor = AppTheme.danger;
      }
      statusDesc = "Đang dùng pin thiết bị";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: focusedIndex == 1 ? AppTheme.primary : AppTheme.cardBorder,
          width: focusedIndex == 1 ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon pin với hiệu ứng nền
              Container(
                width: AppTheme.scaled(36),
                height: AppTheme.scaled(36),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  batteryIcon,
                  size: AppTheme.scaled(20),
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),

              // Thông tin mức pin
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          hasBattery ? "$percent%" : "Nguồn điện AC",
                          style: TextStyle(
                            fontSize: AppTheme.scaled(15),
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (isCharging) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.bolt_rounded,
                                  size: 11,
                                  color: AppTheme.success,
                                ),
                                Text(
                                  "SẠC",
                                  style: TextStyle(
                                    fontSize: AppTheme.scaled(9),
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(statusDesc, style: AppTheme.caption),
                  ],
                ),
              ),

              // Đèn LED trạng thái sạc
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (hasBattery) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100.0,
                minHeight: 5,
                backgroundColor: AppTheme.secondary.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Khối hiển thị các chỉ số phần cứng (CPU, GPU, RAM)
  Widget _buildHardwareGrid() {
    final cpuColor = telemetry.cpuUsagePercent > 85
        ? AppTheme.danger
        : (telemetry.cpuUsagePercent > 50
              ? AppTheme.warning
              : AppTheme.cpuAccent);

    final ramColor = telemetry.ramUsagePercent > 85
        ? AppTheme.danger
        : AppTheme.ramAccent;

    return Column(
      children: [
        // Hàng 1: CPU và RAM
        Row(
          children: [
            // Thẻ CPU
            Expanded(
              child: _buildMetricTile(
                icon: Icons.memory_rounded,
                title: "CPU",
                valueText: "${telemetry.cpuUsagePercent}%",
                subtitle: "$liveTdp W",
                progressValue: telemetry.cpuUsagePercent / 100.0,
                accentColor: cpuColor,
                isFocused: focusedIndex == 2,
              ),
            ),
            const SizedBox(width: 10),

            // Thẻ RAM
            Expanded(
              child: _buildMetricTile(
                icon: Icons.storage_rounded,
                title: "RAM",
                valueText: "${telemetry.ramUsagePercent}%",
                subtitle:
                    "${telemetry.ramUsedGb.toStringAsFixed(1)}/${telemetry.ramTotalGb.toStringAsFixed(0)}GB",
                progressValue: telemetry.ramUsagePercent / 100.0,
                accentColor: ramColor,
                isFocused: focusedIndex == 3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String title,
    required String valueText,
    required String subtitle,
    required double progressValue,
    required Color accentColor,
    required bool isFocused,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isFocused ? AppTheme.primary : AppTheme.cardBorder,
          width: isFocused ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppTheme.scaled(15), color: accentColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                subtitle,
                style: AppTheme.hint.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valueText,
            style: TextStyle(
              fontSize: AppTheme.scaled(20),
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressValue.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppTheme.secondary.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
