import 'dart:io';
import '../core/logger.dart';
import 'hardware_base.dart';

/// Bộ điều khiển âm lượng hệ thống Windows cho máy Handheld.
class AudioController extends HardwareController {
  static const _logger = AppLogger('AudioControl');
  int _currentVolume = 50;

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

    try {
      // Sử dụng PowerShell để đặt Master Volume qua CoreAudio API
      final psScript = '''
\$wsh = New-Object -ComObject Wscript.Shell
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int f(); int g(); int h(); int j();
    int SetMasterVolumeLevelScalar(float fLevel, System.Guid pguidEventContext);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref System.Guid id, int clsCtx, int opt, [MarshalAs(UnmanagedType.IUnknown)] out object pInterface);
}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDevApi {}
public class Audio {
    public static void SetVolume(float vol) {
        var enumerator = (IMMDeviceEnumerator)(new MMDevApi());
        IMMDevice dev = null;
        enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
        var iid = typeof(IAudioEndpointVolume).GUID;
        object epv = null;
        dev.Activate(ref iid, 23, 0, out epv);
        var v = (IAudioEndpointVolume)epv;
        v.SetMasterVolumeLevelScalar(vol, Guid.Empty);
    }
}
"@
[Audio]::SetVolume(${target / 100.0})
''';
      Process.run('powershell', ['-NoProfile', '-Command', psScript]).then((res) {
        if (res.exitCode != 0) {
          _logger.warning('Điều chỉnh âm lượng trả về mã lỗi: ${res.exitCode}');
        }
      });
      _logger.info('Đã cập nhật âm lượng: $target%');
      return true;
    } catch (e) {
      _logger.error('Lỗi khi thiết lập âm lượng', e);
      return false;
    }
  }
}
