import '../core/config.dart';

/// Kiểu bố cục hiển thị lớp phủ RTSS OSD trên màn hình trò chơi.
enum RtssOsdLayout {
  compact('Thu gọn (1 dòng)'),
  vertical('Chi tiết (Nhiều dòng)');

  final String label;
  const RtssOsdLayout(this.label);
}

/// Cấu hình các mục dữ liệu và định dạng hiển thị trên RTSS OSD.
class RtssOsdMetricsConfig {
  final bool showFps;
  final bool showTdp;
  final bool showCpuTemp;
  final bool showCpuUsage;
  final bool showRam;
  final bool showBattery;
  final bool showFan;
  final RtssOsdLayout layout;

  const RtssOsdMetricsConfig({
    this.showFps = true,
    this.showTdp = true,
    this.showCpuTemp = true,
    this.showCpuUsage = false,
    this.showRam = true,
    this.showBattery = true,
    this.showFan = false,
    this.layout = RtssOsdLayout.compact,
  });

  RtssOsdMetricsConfig copyWith({
    bool? showFps,
    bool? showTdp,
    bool? showCpuTemp,
    bool? showCpuUsage,
    bool? showRam,
    bool? showBattery,
    bool? showFan,
    RtssOsdLayout? layout,
  }) {
    return RtssOsdMetricsConfig(
      showFps: showFps ?? this.showFps,
      showTdp: showTdp ?? this.showTdp,
      showCpuTemp: showCpuTemp ?? this.showCpuTemp,
      showCpuUsage: showCpuUsage ?? this.showCpuUsage,
      showRam: showRam ?? this.showRam,
      showBattery: showBattery ?? this.showBattery,
      showFan: showFan ?? this.showFan,
      layout: layout ?? this.layout,
    );
  }

  factory RtssOsdMetricsConfig.fromConfig(ConfigManager config) {
    final layoutStr = config.get("hardware.rtss.osd_layout", "compact");
    final layout = RtssOsdLayout.values.firstWhere(
      (e) => e.name == layoutStr,
      orElse: () => RtssOsdLayout.compact,
    );

    return RtssOsdMetricsConfig(
      showFps: config.get("hardware.rtss.osd_show_fps", true),
      showTdp: config.get("hardware.rtss.osd_show_tdp", true),
      showCpuTemp: config.get("hardware.rtss.osd_show_cpu_temp", true),
      showCpuUsage: config.get("hardware.rtss.osd_show_cpu_usage", false),
      showRam: config.get("hardware.rtss.osd_show_ram", true),
      showBattery: config.get("hardware.rtss.osd_show_battery", true),
      showFan: config.get("hardware.rtss.osd_show_fan", false),
      layout: layout,
    );
  }

  void saveToConfig(ConfigManager config) {
    config.set("hardware.rtss.osd_show_fps", showFps);
    config.set("hardware.rtss.osd_show_tdp", showTdp);
    config.set("hardware.rtss.osd_show_cpu_temp", showCpuTemp);
    config.set("hardware.rtss.osd_show_cpu_usage", showCpuUsage);
    config.set("hardware.rtss.osd_show_ram", showRam);
    config.set("hardware.rtss.osd_show_battery", showBattery);
    config.set("hardware.rtss.osd_show_fan", showFan);
    config.set("hardware.rtss.osd_layout", layout.name);
  }
}

/// Bộ định dạng chuỗi RTSS Markup Tags chuẩn từ các cảm biến thời gian thực.
class RtssOsdFormatter {
  static String format({
    required RtssOsdMetricsConfig config,
    int? fps,
    int? liveTdp,
    int? liveFan,
    double? cpuTemp,
    double? cpuUsage,
    double? ramUsedGb,
    int? batteryPercent,
  }) {
    final items = <String>[];

    // 1. Tốc độ khung hình (FPS)
    if (config.showFps && fps != null && fps > 0) {
      items.add('<C=FFFF00>FPS: $fps<C>');
    }

    // 2. Nhiệt độ CPU (C - thuần ASCII tránh lỗi texture font RTSS)
    if (config.showCpuTemp && cpuTemp != null && cpuTemp > 0) {
      final tempColor = cpuTemp >= 85
          ? 'FF4500' // Đỏ cảnh báo nguy hiểm
          : (cpuTemp >= 75 ? 'FFA500' : '00FF7F'); // Cam hoặc Xanh lá mát
      items.add('<C=$tempColor>${cpuTemp.toStringAsFixed(0)}C<C>');
    }

    // 3. Công suất CPU (TDP Watt)
    if (config.showTdp && liveTdp != null && liveTdp > 0) {
      items.add('<C=00FFFF>TDP: ${liveTdp}W<C>');
    }

    // 4. Mức tải CPU (%)
    if (config.showCpuUsage && cpuUsage != null && cpuUsage >= 0) {
      items.add('<C=E0E0E0>CPU: ${cpuUsage.toStringAsFixed(0)}%<C>');
    }

    // 5. Dung lượng bộ nhớ RAM (GB)
    if (config.showRam && ramUsedGb != null && ramUsedGb > 0) {
      items.add('<C=DDA0DD>RAM: ${ramUsedGb.toStringAsFixed(1)}G<C>');
    }

    // 6. Dung lượng pin (%)
    if (config.showBattery && batteryPercent != null && batteryPercent >= 0) {
      final batColor = batteryPercent <= 20 ? 'FF4500' : '00FF7F';
      items.add('<C=$batColor>BAT: $batteryPercent%<C>');
    }

    // 7. Tốc độ quạt (%)
    if (config.showFan && liveFan != null && liveFan >= 0) {
      items.add('<C=87CEEB>FAN: $liveFan%<C>');
    }

    if (items.isEmpty) {
      return '';
    }

    // Bố cục hiển thị
    if (config.layout == RtssOsdLayout.compact) {
      return items.join(' <C=808080>|<C> ');
    } else {
      return items.join('\r\n');
    }
  }
}
