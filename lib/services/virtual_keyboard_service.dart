import 'dart:io';
import '../core/logger.dart';

/// Dịch vụ điều khiển Bàn phím ảo Windows Touch Keyboard (TabTip)
/// Sử dụng phương thức chuẩn ITipInvocation.Toggle() tương tự như Handheld Companion.
class VirtualKeyboardService {
  static const _logger = AppLogger('VirtualKeyboard');

  /// Kích hoạt Toggle bàn phím ảo (Touch Keyboard) của Windows 10/11.
  static Future<bool> toggleKeyboard() async {
    _logger.info('Sending ITipInvocation.Toggle() command to toggle virtual keyboard...');

    // Lệnh PowerShell chuẩn kích hoạt COM Interface ITipInvocation::Toggle
    const psScript = '''
\$code = @"
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("37c994e7-432b-4834-a2f7-dce1f13b834b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITipInvocation {
    [PreserveSig]
    int Toggle(IntPtr hwndDesktop);
}
public class TouchKeyboard {
    [DllImport("user32.dll")]
    public static extern IntPtr GetDesktopWindow();
    public static int Toggle() {
        try {
            var clsid = new Guid("4ce576fa-83dc-4f88-951c-9d0782b4e376");
            var type = Type.GetTypeFromCLSID(clsid);
            var instance = (ITipInvocation)Activator.CreateInstance(type);
            return instance.Toggle(GetDesktopWindow());
        } catch {
            return -1;
        }
    }
}
"@
Add-Type -TypeDefinition \$code
[TouchKeyboard]::Toggle()
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
      );

      final output = result.stdout.toString().trim();
      if (output == '0') {
        _logger.info('Called ITipInvocation.Toggle() successfully (S_OK).');
        return true;
      } else {
        _logger.warning('ITipInvocation returned error code: $output. Attempting TabTip fallback.');
      }
    } catch (e) {
      _logger.error('Error triggering ITipInvocation via PowerShell', e);
    }

    // Fallback: Chạy trực tiếp TabTip.exe nếu COM chưa kích hoạt
    final tabTipPaths = [
      r'C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe',
      r'C:\Program Files (x86)\Common Files\microsoft shared\ink\TabTip.exe',
    ];

    for (final path in tabTipPaths) {
      if (File(path).existsSync()) {
        try {
          await Process.start(path, [], runInShell: true);
          _logger.info('Launched fallback TabTip.exe: $path');
          return true;
        } catch (_) {}
      }
    }

    return false;
  }
}
