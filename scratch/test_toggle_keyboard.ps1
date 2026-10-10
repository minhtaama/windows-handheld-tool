$code = @"
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
        } catch (Exception ex) {
            Console.WriteLine(ex.ToString());
            return -1;
        }
    }
}
"@
Add-Type -TypeDefinition $code
$res = [TouchKeyboard]::Toggle()
Write-Host "RESULT: $res"
