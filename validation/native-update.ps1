param([string]$Report,[string]$ApplicationExe=(Join-Path $env:LOCALAPPDATA 'Programs/RiyadaCahier-UpdateTest/RiyadaCahier.exe'))
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class RiyadaNative {
 public delegate bool EnumProc(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc c,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc c,IntPtr p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint timeout,out IntPtr r);
 public static List<IntPtr> Windows(){var a=new List<IntPtr>();EnumWindows((h,p)=>{a.Add(h);return true;},IntPtr.Zero);return a;}
 public static List<IntPtr> Children(IntPtr parent){var a=new List<IntPtr>();EnumChildWindows(parent,(h,p)=>{a.Add(h);return true;},IntPtr.Zero);return a;}
 public static string Text(IntPtr h){var s=new StringBuilder(1024);GetWindowText(h,s,s.Capacity);return s.ToString();}
 public static string Class(IntPtr h){var s=new StringBuilder(256);GetClassName(h,s,s.Capacity);return s.ToString();}
 public static void Click(IntPtr h){IntPtr r;SendMessageTimeout(h,0x00F5,IntPtr.Zero,IntPtr.Zero,2,2000,out r);}
}
"@
$clicked = @()
$inventory = @()
$deadline = (Get-Date).AddMinutes(4)
while ((Get-Date) -lt $deadline) {
    $allowed = @{}
    foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($process.Path -eq $ApplicationExe -or $process.Path -like (Join-Path $env:LOCALAPPDATA 'riyadacahier-desktop-test-updater\*')) { $allowed[[uint32]$process.Id]=$true }
        } catch {}
    }
    foreach ($window in [RiyadaNative]::Windows()) {
        [uint32]$processIdValue=0
        [RiyadaNative]::GetWindowThreadProcessId($window,[ref]$processIdValue) | Out-Null
        if (-not $allowed.ContainsKey($processIdValue)) { continue }
        foreach ($button in [RiyadaNative]::Children($window)) {
            if ([RiyadaNative]::Class($button) -ne 'Button' -or -not [RiyadaNative]::IsWindowVisible($button) -or -not [RiyadaNative]::IsWindowEnabled($button)) { continue }
            $name=([RiyadaNative]::Text($button)).Replace('&','').Trim() -replace '[\u200e\u200f\u202a-\u202e\u2066-\u2069]',''
            if ($name -and $name -notin $inventory) { $inventory += $name }
            if ($name -notmatch '^(إغلاق وتثبيت|Fermer et installer|Suivant|Next|Installer|Install|Terminer|Finish|Fermer$|التالي|تثبيت|إنهاء)') { continue }
            [RiyadaNative]::Click($button)
            $clicked += $name
            @{buttons=$clicked;visibleButtonNames=$inventory;finished=($name -match '^(Terminer|Finish|Fermer|إنهاء)$')} | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $Report
            if ($name -match '^(Terminer|Finish|Fermer|إنهاء)$') { exit 0 }
            Start-Sleep -Milliseconds 800
            break
        }
    }
    Start-Sleep -Milliseconds 250
}
@{buttons=$clicked;visibleButtonNames=$inventory;finished=$false;timedOut=$true} | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $Report
exit 1
