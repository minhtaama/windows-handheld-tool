import '../services/system_telemetry_service.dart';

/// Predefined color palettes for quick selection.
class RtssColorPalettes {
  static const Map<String, String> defaultPalette = {
    'fps': 'FFFF00',
    'tdp': '00FFFF',
    'cpu_temp': 'FFA500',
    'cpu_usage': 'E0E0E0',
    'ram': 'DDA0DD',
    'battery': '00FF7F',
    'time_left': '87CEFA',
    'fan': '87CEEB',
  };

  static const Map<String, String> neonCyberpunk = {
    'fps': '00FFCC',
    'tdp': 'FF007F',
    'cpu_temp': 'FF3366',
    'cpu_usage': '33CCFF',
    'ram': 'CC00FF',
    'battery': '00FF66',
    'time_left': 'FFCC00',
    'fan': '00E5FF',
  };

  static const Map<String, String> amberRetro = {
    'fps': 'FFB000',
    'tdp': 'FF8000',
    'cpu_temp': 'FF5500',
    'cpu_usage': 'FFCC00',
    'ram': 'E5A600',
    'battery': 'FFD700',
    'time_left': 'FFA040',
    'fan': 'D48800',
  };

  static const Map<String, String> minimalWhite = {
    'fps': 'FFFFFF',
    'tdp': 'CCCCCC',
    'cpu_temp': 'EAEAEA',
    'cpu_usage': 'B0B0B0',
    'ram': 'D0D0D0',
    'battery': 'FFFFFF',
    'time_left': 'A0A0A0',
    'fan': 'BEBEBE',
  };

  static const Map<String, Map<String, String>> all = {
    'Mặc định': defaultPalette,
    'Neon Cyber': neonCyberpunk,
    'Amber Retro': amberRetro,
    'Trắng tối giản': minimalWhite,
  };
}

/// Token description metadata for UI HelpBox and quick-insert chips.
class RtssTokenInfo {
  final String token;
  final String label;
  final String description;
  final String example;

  const RtssTokenInfo({
    required this.token,
    required this.label,
    required this.description,
    required this.example,
  });
}

/// High-performance compiler and parser for RTSS In-Game Overlay text tags.
class RtssSyntaxParser {
  /// All available tokens for UI reference.
  static const List<RtssTokenInfo> availableTokens = [
    RtssTokenInfo(
      token: '{fps}',
      label: 'FPS',
      description: 'Instantaneous frame rate',
      example: '60',
    ),
    RtssTokenInfo(
      token: '{tdp}',
      label: 'TDP (W)',
      description: 'Current package power in Watts',
      example: '15',
    ),
    RtssTokenInfo(
      token: '{cpu_temp}',
      label: 'Nhiệt độ CPU',
      description: 'CPU temperature in Celsius',
      example: '68',
    ),
    RtssTokenInfo(
      token: '{cpu_usage}',
      label: 'Tải CPU (%)',
      description: 'CPU utilization percentage',
      example: '42',
    ),
    RtssTokenInfo(
      token: '{ram_used}',
      label: 'RAM dùng (GB)',
      description: 'Allocated system RAM in Gigabytes',
      example: '8.4',
    ),
    RtssTokenInfo(
      token: '{ram_total}',
      label: 'Tổng RAM (GB)',
      description: 'Total installed RAM in Gigabytes',
      example: '16',
    ),
    RtssTokenInfo(
      token: '{ram_percent}',
      label: 'Tải RAM (%)',
      description: 'Memory usage percentage',
      example: '52',
    ),
    RtssTokenInfo(
      token: '{battery}',
      label: 'Mức pin (%)',
      description: 'Battery charge level percentage',
      example: '85',
    ),
    RtssTokenInfo(
      token: '{time_left}',
      label: 'Thời gian pin',
      description: 'Estimated remaining battery time',
      example: '1h45m / CHG',
    ),
    RtssTokenInfo(
      token: '{fan}',
      label: 'Tốc độ quạt',
      description: 'Fan speed percentage',
      example: '45',
    ),
    RtssTokenInfo(
      token: '{time}',
      label: 'Giờ hệ thống',
      description: 'Current 24h clock time',
      example: '14:30',
    ),
    RtssTokenInfo(
      token: '{game}',
      label: 'Tên Game',
      description: 'Running active game executable',
      example: 'EldenRing.exe',
    ),
    RtssTokenInfo(
      token: '{cpu_temp_color}',
      label: 'Màu nhiệt động',
      description: 'Adaptive color hex (Green/Orange/Red by temp)',
      example: '00FF7F',
    ),
    RtssTokenInfo(
      token: '{fps_color}',
      label: 'Màu FPS động',
      description: 'Adaptive color hex (Red < 30, Yellow < 55, Green >= 60)',
      example: '00FF7F',
    ),
    RtssTokenInfo(
      token: '{bat_color}',
      label: 'Màu pin động',
      description: 'Adaptive color hex (Red <= 20%, Green > 20%)',
      example: '00FF7F',
    ),
  ];

  /// Compiles a template string into RTSS markup by substituting tokens with live values.
  static String compile({
    required String template,
    required SystemTelemetryData telem,
    int? fps,
    String? game,
  }) {
    if (template.isEmpty) return '';

    // Calculate dynamic threshold colors
    final temp = telem.cpuTemp ?? 0;
    final tempColor = temp >= 85
        ? 'FF4500' // Red
        : (temp >= 75 ? 'FFA500' : '00FF7F'); // Orange / Green

    final liveFps = fps ?? telem.liveFps ?? 0;
    final fpsColor = liveFps < 30
        ? 'FF4500' // Red
        : (liveFps < 55 ? 'FFFF00' : '00FF7F'); // Yellow / Green

    final batPct = telem.batteryPercent ?? 100;
    final batColor = batPct <= 20 ? 'FF4500' : '00FF7F';

    // Direct token substitution
    String output = template;

    output = output.replaceAll('{fps}', liveFps > 0 ? '$liveFps' : '--');
    output = output.replaceAll(
      '{tdp}',
      telem.liveTdp != null ? '${telem.liveTdp}' : '--',
    );
    output = output.replaceAll(
      '{cpu_temp}',
      telem.cpuTemp != null ? '${telem.cpuTemp}' : '--',
    );
    output = output.replaceAll('{cpu_usage}', '${telem.cpuUsagePercent}');
    output = output.replaceAll('{ram_used}', telem.ramUsedGb.toStringAsFixed(1));
    output = output.replaceAll('{ram_total}', telem.ramTotalGb.toStringAsFixed(0));
    output = output.replaceAll('{ram_percent}', '${telem.ramUsagePercent}');
    output = output.replaceAll(
      '{battery}',
      telem.batteryPercent != null ? '${telem.batteryPercent}' : '--',
    );
    output = output.replaceAll('{time_left}', telem.batteryTimeLeftFormatted);
    output = output.replaceAll('{fan}', '${telem.liveFan}');
    output = output.replaceAll('{time}', telem.timeString);
    output = output.replaceAll(
      '{game}',
      game ?? telem.activeGame ?? 'Desktop',
    );

    // Dynamic color tags
    output = output.replaceAll('{cpu_temp_color}', tempColor);
    output = output.replaceAll('{fps_color}', fpsColor);
    output = output.replaceAll('{bat_color}', batColor);

    // Convert literal escaped newlines to actual CRLF for RTSS
    output = output.replaceAll('\\n', '\r\n');

    return output;
  }
}
