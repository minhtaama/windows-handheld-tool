import 'dart:io';
import '../core/logger.dart';
import 'hardware_base.dart';

/// Bộ điều khiển âm lượng hệ thống Windows cho máy Handheld qua Windows CoreAudio API.
class AudioController extends HardwareController {
  static const _logger = AppLogger('AudioControl');
  int _currentVolume = 50;
  bool _isSettingVolume = false;
  int? _pendingVolume;

  AudioController({
    super.minVal = 0,
    super.maxVal = 100,
    super.step = 2,
    int defaultVal = 50,
  })  : _currentVolume = defaultVal,
        super(
          name: "Âm lượng",
          unit: "%",
        );

  @override
  bool isAvailable() => true;

  @override
  int getValue() => _currentVolume;

  @override
  bool setValue(int value) {
    final target = clamp(value);
    _currentVolume = target;
    _applyVolume(target);
    return true;
  }

  void _applyVolume(int target) {
    if (_isSettingVolume) {
      _pendingVolume = target;
      return;
    }
    _isSettingVolume = true;
    _pendingVolume = null;

    final psScript = '''
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
    int f(); int g(); int h(); int i();
    int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume aev);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int f();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject {}

public class AudioControl {
    public static void SetVolume(float level) {
        var enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
        IMMDevice dev = null;
        enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
        IAudioEndpointVolume epv = null;
        var epvid = typeof(IAudioEndpointVolume).GUID;
        dev.Activate(ref epvid, 23, 0, out epv);
        epv.SetMasterVolumeLevelScalar(level, Guid.Empty);
        Marshal.ReleaseComObject(epv);
        Marshal.ReleaseComObject(dev);
    }
}
'@
[AudioControl]::SetVolume(${target / 100.0})
''';

    Process.run('powershell', ['-NoProfile', '-Command', psScript]).then((res) {
      _isSettingVolume = false;
      if (res.exitCode != 0) {
        _logger.warning('Điều chỉnh âm lượng trả về mã lỗi: ${res.exitCode}');
      }
      if (_pendingVolume != null) {
        final next = _pendingVolume!;
        _pendingVolume = null;
        _applyVolume(next);
      }
    }).catchError((e) {
      _isSettingVolume = false;
      _logger.error('Lỗi khi thiết lập âm lượng', e);
    });
  }
}

