import 'dart:async';
import '../core/config.dart';
import '../core/logger.dart';
import '../services/system_telemetry_service.dart';
import 'rtss_osd_formatter.dart';
import 'rtss_service.dart';

/// Background daemon service that continuously updates RTSS In-Game OSD
/// according to telemetry broadcasts, independent of UI Tab lifecycle.
class RtssOsdService {
  static const _logger = AppLogger('RtssOsdService');
  static final RtssOsdService instance = RtssOsdService._();

  StreamSubscription<SystemTelemetryData>? _telemetrySub;
  bool _osdEnabled = true;
  RtssOsdMetricsConfig _metricsConfig = const RtssOsdMetricsConfig();
  bool _isInitialized = false;

  RtssOsdService._();

  bool get isOsdEnabled => _osdEnabled;
  RtssOsdMetricsConfig get metricsConfig => _metricsConfig;

  /// Initializes the background OSD worker with the stored configuration.
  void init(ConfigManager config) {
    if (_isInitialized) return;
    _isInitialized = true;

    _osdEnabled = config.get("hardware.rtss.osd_enabled", true);
    _metricsConfig = RtssOsdMetricsConfig.fromConfig(config);

    _telemetrySub = SystemTelemetryService.instance.telemetryStream.listen(
      _onTelemetryTick,
      onError: (err) => _logger.error('Telemetry stream error in OSD service: $err'),
    );

    _logger.info('RtssOsdService initialized. OSD enabled: $_osdEnabled');
  }

  /// Updates OSD enabled status and clears OSD text if disabled.
  void setOsdEnabled(bool enabled, {ConfigManager? config}) {
    _osdEnabled = enabled;
    RtssService.instance.setOsdEnabled(enabled);
    if (config != null) {
      config.set("hardware.rtss.osd_enabled", enabled);
    }
    if (!enabled) {
      RtssService.instance.clearOsdText();
    } else {
      // Force immediate refresh with latest telemetry
      _onTelemetryTick(SystemTelemetryService.instance.latest);
    }
  }

  /// Updates current metrics/syntax configuration.
  void updateConfig(RtssOsdMetricsConfig newConfig, {ConfigManager? config}) {
    _metricsConfig = newConfig;
    if (config != null) {
      newConfig.saveToConfig(config);
    }
    if (_osdEnabled) {
      _onTelemetryTick(SystemTelemetryService.instance.latest);
    }
  }

  void _onTelemetryTick(SystemTelemetryData telem) {
    if (!_osdEnabled) return;

    final text = RtssOsdFormatter.format(
      config: _metricsConfig,
      telem: telem,
      fps: telem.liveFps,
      game: telem.activeGame,
    );

    RtssService.instance.updateOsdText(text);
  }

  void dispose() {
    _telemetrySub?.cancel();
    _telemetrySub = null;
    _isInitialized = false;
  }
}
