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
using System.Collections.Generic;

public class MonitorController {

    // --- VCP codes ---
    public const byte VCP_POWER_MODE   = 0xD6;  // Power mode (MCCS standard)
    public const byte VCP_DPMS_CONTROL = 0x01;  // DPMS/standby (fallback)

    // VCP 0xD6 values
    public const uint VCP_POWER_ON      = 0x01;
    public const uint VCP_POWER_STANDBY = 0x02;
    public const uint VCP_POWER_SUSPEND = 0x03;
    public const uint VCP_POWER_OFF     = 0x05;

    [StructLayout(LayoutKind.Sequential)]
    public struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MC_VCP_CODE_TYPE { }

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumDelegate lpfnEnum, IntPtr dwData);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint pdwNumberOfPhysicalMonitors);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitors(uint dwPhysicalMonitorArraySize, [In] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode, uint dwNewValue);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetVCPFeatureAndVCPFeatureReply(
        IntPtr hMonitor, byte bVCPCode, IntPtr pvct,
        out uint pdwCurrentValue, out uint pdwMaximumValue);

    // WinAPI fallback: send generic monitor-off message
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    private const uint WM_SYSCOMMAND  = 0x0112;
    private static readonly IntPtr SC_MONITORPOWER = new IntPtr(0xF170);
    private static readonly IntPtr MONITOR_OFF     = new IntPtr(2);
    private static readonly IntPtr HWND_BROADCAST  = new IntPtr(0xFFFF);

    private delegate bool MonitorEnumDelegate(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

    // Results collected during enumeration
    public static List<string> Warnings = new List<string>();
    public static List<string> Info     = new List<string>();

    public static void TurnOffAllMonitors() {
        Warnings.Clear();
        Info.Clear();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, new MonitorEnumDelegate(MonitorEnumProc), IntPtr.Zero);
    }

    private static bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData) {
        uint physicalMonitorCount = 0;
        if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out physicalMonitorCount)) {
            Warnings.Add("Unable to enumerate a logical monitor (GetNumberOfPhysicalMonitors failed).");
            return true;
        }

        PHYSICAL_MONITOR[] physicalMonitors = new PHYSICAL_MONITOR[physicalMonitorCount];
        if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, physicalMonitorCount, physicalMonitors)) {
            Warnings.Add("Unable to get physical monitors from a logical monitor.");
            return true;
        }

        foreach (PHYSICAL_MONITOR pm in physicalMonitors) {
            string name = string.IsNullOrWhiteSpace(pm.szPhysicalMonitorDescription)
                          ? "(unnamed monitor)"
                          : pm.szPhysicalMonitorDescription;

            bool ddcOk = IsDDCSupported(pm.hPhysicalMonitor, VCP_POWER_MODE);

            if (ddcOk) {
                // --- Determine the correct OFF value for this monitor ---
                uint bestValue = GetBestOffValue(pm.hPhysicalMonitor);
                string label   = ValueLabel(bestValue);
                bool sent      = SetVCPFeature(pm.hPhysicalMonitor, VCP_POWER_MODE, bestValue);

                if (sent) {
                    Info.Add(string.Format("[DDC/CI] {0} -> VCP 0xD6 = {1} ({2})", name, bestValue, label));
                } else {
                    // VCP 0xD6 failed; try DPMS standby via VCP 0x01
                    bool dpms = SetVCPFeature(pm.hPhysicalMonitor, VCP_DPMS_CONTROL, 0x02);
                    if (dpms) {
                        Info.Add(string.Format("[DDC/CI DPMS] {0} -> VCP 0x01 = standby", name));
                    } else {
                        Warnings.Add(string.Format("[DDC/CI] {0}: VCP command failed, using WinAPI fallback.", name));
                        SendMessage(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, MONITOR_OFF);
                    }
                }
            } else {
                // Monitor does NOT support DDC/CI
                Warnings.Add(string.Format("[No DDC/CI] {0}: DDC/CI not supported or disabled. Using WinAPI fallback.", name));
                SendMessage(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, MONITOR_OFF);
            }
        }

        DestroyPhysicalMonitors(physicalMonitorCount, physicalMonitors);
        return true;
    }

    // Check whether VCP code 0xD6 is readable (= DDC/CI active)
    private static bool IsDDCSupported(IntPtr hMonitor, byte vcpCode) {
        uint cur, max;
        return GetVCPFeatureAndVCPFeatureReply(hMonitor, vcpCode, IntPtr.Zero, out cur, out max);
    }

    // Return the most appropriate OFF value supported by this monitor.
    // Preference order: 0x05 (off) > 0x04 (off+save) > 0x03 (suspend) > 0x02 (standby)
    private static uint GetBestOffValue(IntPtr hMonitor) {
        uint cur, max;
        if (!GetVCPFeatureAndVCPFeatureReply(hMonitor, VCP_POWER_MODE, IntPtr.Zero, out cur, out max)) {
            return VCP_POWER_OFF; // default, will likely fail too but worth trying
        }

        // max tells us how many states the monitor declares; use it as a guide.
        // MCCS: 1=on, 2=standby, 3=suspend, 4=off+save-settings, 5=off
        uint[] preferred = new uint[] { 0x05, 0x04, 0x03, 0x02 };
        foreach (uint v in preferred) {
            if (v <= max) return v;
        }
        return VCP_POWER_OFF;
    }

    private static string ValueLabel(uint v) {
        switch (v) {
            case 0x02: return "standby";
            case 0x03: return "suspend";
            case 0x04: return "off (save settings)";
            case 0x05: return "off";
            default:   return "unknown";
        }
    }
}
"@

# 2. Compilation
try {
    Add-Type -TypeDefinition $code -Language CSharp
} catch {
    # Ignore if type is already loaded in this session
}

# 3. Run Monitor Shutdown
Write-Host ""
Write-Host "=== MonitorGuard ===" -ForegroundColor White
Write-Host "Sending power-off signal to all monitors..." -ForegroundColor Cyan
Write-Host ""

[MonitorController]::TurnOffAllMonitors()

# 4. Show per-monitor results
foreach ($msg in [MonitorController]::Info) {
    Write-Host "  OK  $msg" -ForegroundColor Green
}
foreach ($warn in [MonitorController]::Warnings) {
    Write-Host "  !!  $warn" -ForegroundColor Yellow
}

if ([MonitorController]::Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Note: monitors marked '!!' do not support DDC/CI or had a VCP error." -ForegroundColor Yellow
    Write-Host "      A generic WinAPI off signal was sent as fallback." -ForegroundColor Yellow
    Write-Host "      To enable DDC/CI: check your monitor's OSD menu." -ForegroundColor Yellow
}

# 5. PC shutdown (wait to ensure signals are delivered)
Write-Host ""
Start-Sleep -Seconds 2
Write-Host "System shutdown..." -ForegroundColor Red
Stop-Computer -Force