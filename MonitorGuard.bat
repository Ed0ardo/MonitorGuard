<# :
@echo off
setlocal
cd /d %~dp0

:: Run this same file interpreting it as PowerShell, bypassing policies
powershell -ExecutionPolicy Bypass -NoProfile -Command "Invoke-Expression ($(Get-Content '%~f0' | Out-String))"
exit /b
#>

# --- START POWERSHELL BLOCK ---

# 1. C# class definition to turn off monitors
$code = @"
using System;
using System.Runtime.InteropServices;

public class MonitorController {
    public const byte VCP_POWER_MODE = 0xD6;
    public const uint VCP_POWER_OFF = 0x05;

    [StructLayout(LayoutKind.Sequential)]
    public struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumDelegate lpfnEnum, IntPtr dwData);

    [DllImport("dxva2.dll")]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint pdwNumberOfPhysicalMonitors);

    [DllImport("dxva2.dll")]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll")]
    private static extern bool DestroyPhysicalMonitors(uint dwPhysicalMonitorArraySize, [In] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll")]
    private static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode, uint dwNewValue);

    private delegate bool MonitorEnumDelegate(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

    public static void TurnOffAllMonitors() {
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, new MonitorEnumDelegate(MonitorEnumProc), IntPtr.Zero);
    }

    private static bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData) {
        uint physicalMonitorCount = 0;
        if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out physicalMonitorCount)) {
            PHYSICAL_MONITOR[] physicalMonitors = new PHYSICAL_MONITOR[physicalMonitorCount];
            if (GetPhysicalMonitorsFromHMONITOR(hMonitor, physicalMonitorCount, physicalMonitors)) {
                foreach (PHYSICAL_MONITOR pm in physicalMonitors) {
                    // Send shutdown command
                    SetVCPFeature(pm.hPhysicalMonitor, VCP_POWER_MODE, VCP_POWER_OFF);
                }
                DestroyPhysicalMonitors(physicalMonitorCount, physicalMonitors);
            }
        }
        return true;
    }
}
"@

# 2. Compilation
try {
    Add-Type -TypeDefinition $code -Language CSharp
} catch {
    # Ignore error if type is already loaded
}

# 3. Run Monitor Shutdown
Write-Host "Turn off the monitors..." -ForegroundColor Cyan
[MonitorController]::TurnOffAllMonitors()

# 4. PC shutdown (Wait 2 seconds to ensure signal is sent to monitors)
Start-Sleep -Seconds 2

Write-Host "System shutdown..." -ForegroundColor Red
# Force = Force close open apps
Stop-Computer -Force