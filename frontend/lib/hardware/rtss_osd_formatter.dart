import '../core/config.dart';
import '../services/system_telemetry_service.dart';
import 'rtss_syntax_parser.dart';

/// Layout orientation for RTSS In-Game OSD.
enum RtssOsdLayout {
  compact('Thu gọn (1 dòng)'),
  vertical('Chi tiết (Nhiều dòng)');

  final String label;
  const RtssOsdLayout(this.label);
}

/// Mode of OSD customization.
enum RtssOsdMode {
  visual('Trực quan (Tùy chọn)'),
  syntax('Cú pháp (Tùy biến)');

  final String label;
  const RtssOsdMode(this.label);
}

/// Configuration settings for metrics, colors, labels, and templates in RTSS OSD.
class RtssOsdMetricsConfig {
  final RtssOsdMode mode;
  final bool showFps;
  final bool showTdp;
  final bool showCpuTemp;
  final bool showCpuUsage;
  final bool showRam;
  final bool showBattery;
  final bool showTimeLeft;
  final bool showFan;
  final RtssOsdLayout layout;
  final String paletteName;
  final Map<String, String> colors;
  final Map<String, String> labels;
  final String customTemplate;

  static const String defaultTemplate =
      '<C=FFFF00>{fps} FPS<C> <C=808080>|<C> <C={cpu_temp_color}>{cpu_temp}C<C> <C=808080>|<C> <C=00FFFF>{tdp}W<C> <C=808080>|<C> <C={bat_color}>{battery}% ({time_left})<C>';

  static const Map<String, String> defaultLabels = {
    'fps': 'FPS',
    'tdp': 'TDP',
    'cpu_temp': 'CPU',
    'cpu_usage': 'CPU',
    'ram': 'RAM',
    'battery': 'BAT',
    'time_left': 'LEFT',
    'fan': 'FAN',
  };

  const RtssOsdMetricsConfig({
    this.mode = RtssOsdMode.visual,
    this.showFps = true,
    this.showTdp = true,
    this.showCpuTemp = true,
    this.showCpuUsage = false,
    this.showRam = true,
    this.showBattery = true,
    this.showTimeLeft = true,
    this.showFan = false,
    this.layout = RtssOsdLayout.compact,
    this.paletteName = 'Mặc định',
    this.colors = RtssColorPalettes.defaultPalette,
    this.labels = defaultLabels,
    this.customTemplate = defaultTemplate,
  });

  RtssOsdMetricsConfig copyWith({
    RtssOsdMode? mode,
    bool? showFps,
    bool? showTdp,
    bool? showCpuTemp,
    bool? showCpuUsage,
    bool? showRam,
    bool? showBattery,
    bool? showTimeLeft,
    bool? showFan,
    RtssOsdLayout? layout,
    String? paletteName,
    Map<String, String>? colors,
    Map<String, String>? labels,
    String? customTemplate,
  }) {
    return RtssOsdMetricsConfig(
      mode: mode ?? this.mode,
      showFps: showFps ?? this.showFps,
      showTdp: showTdp ?? this.showTdp,
      showCpuTemp: showCpuTemp ?? this.showCpuTemp,
      showCpuUsage: showCpuUsage ?? this.showCpuUsage,
      showRam: showRam ?? this.showRam,
      showBattery: showBattery ?? this.showBattery,
      showTimeLeft: showTimeLeft ?? this.showTimeLeft,
      showFan: showFan ?? this.showFan,
      layout: layout ?? this.layout,
      paletteName: paletteName ?? this.paletteName,
      colors: colors ?? this.colors,
      labels: labels ?? this.labels,
      customTemplate: customTemplate ?? this.customTemplate,
    );
  }

  factory RtssOsdMetricsConfig.fromConfig(ConfigManager config) {
    final modeStr = config.get("hardware.rtss.osd_mode", "visual");
    final mode = RtssOsdMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => RtssOsdMode.visual,
    );

    final layoutStr = config.get("hardware.rtss.osd_layout", "compact");
    final layout = RtssOsdLayout.values.firstWhere(
      (e) => e.name == layoutStr,
      orElse: () => RtssOsdLayout.compact,
    );

    final palette = config.get("hardware.rtss.osd_palette", "Mặc định");
    final basePalette = RtssColorPalettes.all[palette] ?? RtssColorPalettes.defaultPalette;

    // Load custom color overrides if saved
    final rawColors = config.get("hardware.rtss.osd_colors", <String, dynamic>{});
    final Map<String, String> resolvedColors = Map.from(basePalette);
    rawColors.forEach((k, v) {
      if (v != null) resolvedColors[k.toString()] = v.toString();
    });

    // Load custom label overrides if saved
    final rawLabels = config.get("hardware.rtss.osd_labels", <String, dynamic>{});
    final Map<String, String> resolvedLabels = Map.from(defaultLabels);
    rawLabels.forEach((k, v) {
      if (v != null) resolvedLabels[k.toString()] = v.toString();
    });

    return RtssOsdMetricsConfig(
      mode: mode,
      showFps: config.get("hardware.rtss.osd_show_fps", true),
      showTdp: config.get("hardware.rtss.osd_show_tdp", true),
      showCpuTemp: config.get("hardware.rtss.osd_show_cpu_temp", true),
      showCpuUsage: config.get("hardware.rtss.osd_show_cpu_usage", false),
      showRam: config.get("hardware.rtss.osd_show_ram", true),
      showBattery: config.get("hardware.rtss.osd_show_battery", true),
      showTimeLeft: config.get("hardware.rtss.osd_show_time_left", true),
      showFan: config.get("hardware.rtss.osd_show_fan", false),
      layout: layout,
      paletteName: palette,
      colors: resolvedColors,
      labels: resolvedLabels,
      customTemplate: config.get("hardware.rtss.osd_custom_template", defaultTemplate),
    );
  }

  void saveToConfig(ConfigManager config) {
    config.set("hardware.rtss.osd_mode", mode.name);
    config.set("hardware.rtss.osd_show_fps", showFps);
    config.set("hardware.rtss.osd_show_tdp", showTdp);
    config.set("hardware.rtss.osd_show_cpu_temp", showCpuTemp);
    config.set("hardware.rtss.osd_show_cpu_usage", showCpuUsage);
    config.set("hardware.rtss.osd_show_ram", showRam);
    config.set("hardware.rtss.osd_show_battery", showBattery);
    config.set("hardware.rtss.osd_show_time_left", showTimeLeft);
    config.set("hardware.rtss.osd_show_fan", showFan);
    config.set("hardware.rtss.osd_layout", layout.name);
    config.set("hardware.rtss.osd_palette", paletteName);
    config.set("hardware.rtss.osd_colors", colors);
    config.set("hardware.rtss.osd_labels", labels);
    config.set("hardware.rtss.osd_custom_template", customTemplate);
  }
}

/// Formatter that generates standard RTSS markup strings from real-time telemetry.
class RtssOsdFormatter {
  static String format({
    required RtssOsdMetricsConfig config,
    required SystemTelemetryData telem,
    int? fps,
    String? game,
  }) {
    // 1. Syntax Mode: user defined custom template
    if (config.mode == RtssOsdMode.syntax) {
      return RtssSyntaxParser.compile(
        template: config.customTemplate,
        telem: telem,
        fps: fps,
        game: game,
      );
    }

    // 2. Visual Mode: dynamic construction from toggles, labels, and color settings
    final items = <String>[];
    final labels = config.labels;
    final colors = config.colors;

    final fpsColor = colors['fps'] ?? 'FFFF00';
    final tdpColor = colors['tdp'] ?? '00FFFF';
    final cpuTempColor = colors['cpu_temp'] ?? 'FFA500';
    final cpuUsageColor = colors['cpu_usage'] ?? 'E0E0E0';
    final ramColor = colors['ram'] ?? 'DDA0DD';
    final batColor = colors['battery'] ?? '00FF7F';
    final timeLeftColor = colors['time_left'] ?? '87CEFA';
    final fanColor = colors['fan'] ?? '87CEEB';

    // 1. Frame rate (FPS)
    final liveFps = fps ?? telem.liveFps;
    if (config.showFps && liveFps != null && liveFps > 0) {
      final lbl = labels['fps']?.trim() ?? 'FPS';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$fpsColor>$prefix$liveFps<C>');
    }

    // 2. CPU Temperature (C)
    if (config.showCpuTemp && telem.cpuTemp != null && telem.cpuTemp! > 0) {
      final dynamicColor = telem.cpuTemp! >= 85
          ? 'FF4500'
          : (telem.cpuTemp! >= 75 ? 'FFA500' : cpuTempColor);
      final lbl = labels['cpu_temp']?.trim() ?? 'CPU';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$dynamicColor>$prefix${telem.cpuTemp}C<C>');
    }

    // 3. CPU Power (TDP Watt)
    if (config.showTdp && telem.liveTdp != null && telem.liveTdp! > 0) {
      final lbl = labels['tdp']?.trim() ?? 'TDP';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$tdpColor>$prefix${telem.liveTdp}W<C>');
    }

    // 4. CPU Usage (%)
    if (config.showCpuUsage && telem.cpuUsagePercent >= 0) {
      final lbl = labels['cpu_usage']?.trim() ?? 'CPU';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$cpuUsageColor>$prefix${telem.cpuUsagePercent}%<C>');
    }

    // 5. Memory RAM (GB)
    if (config.showRam && telem.ramUsedGb > 0) {
      final lbl = labels['ram']?.trim() ?? 'RAM';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$ramColor>$prefix${telem.ramUsedGb.toStringAsFixed(1)}G<C>');
    }

    // 6. Battery (%) & Time Left
    if (config.showBattery && telem.batteryPercent != null && telem.batteryPercent! >= 0) {
      final dynamicBatColor = telem.batteryPercent! <= 20 ? 'FF4500' : batColor;
      final lbl = labels['battery']?.trim() ?? 'BAT';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      
      String batStr = '<C=$dynamicBatColor>$prefix${telem.batteryPercent}%<C>';
      if (config.showTimeLeft) {
        batStr += ' <C=$timeLeftColor>(${telem.batteryTimeLeftFormatted})<C>';
      }
      items.add(batStr);
    } else if (config.showTimeLeft) {
      final lbl = labels['time_left']?.trim() ?? 'LEFT';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$timeLeftColor>$prefix${telem.batteryTimeLeftFormatted}<C>');
    }

    // 7. Fan Speed (%)
    if (config.showFan && telem.liveFan >= 0) {
      final lbl = labels['fan']?.trim() ?? 'FAN';
      final prefix = lbl.isNotEmpty ? '$lbl: ' : '';
      items.add('<C=$fanColor>$prefix${telem.liveFan}%<C>');
    }

    if (items.isEmpty) return '';

    // Layout arrangement
    if (config.layout == RtssOsdLayout.compact) {
      return items.join(' <C=808080>|<C> ');
    } else {
      return items.join('\r\n');
    }
  }
}
