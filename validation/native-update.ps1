param([string]$Report)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$clicked = @()
$deadline = (Get-Date).AddMinutes(4)
while ((Get-Date) -lt $deadline) {
    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($window in $windows) {
        try {
            $title = $window.Current.Name
            if ($title -notmatch '(^تحديث البرنامج$|^Mise à jour$|Riyada Cahier Update Test)') { continue }
            $buttons = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)))
            foreach ($button in $buttons) {
                $name = $button.Current.Name.Replace('&','').Trim()
                if (-not $button.Current.IsEnabled -or $button.Current.IsOffscreen -or $name -notmatch '^(إغلاق وتثبيت|Fermer et installer|Suivant|Next|Installer|Install|Terminer|Finish|Fermer$|التالي|تثبيت|إنهاء)') { continue }
                $invoke = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                $invoke.Invoke()
                $clicked += $name
                @{ buttons=$clicked; finished=($name -match '^(Terminer|Finish|Fermer|إنهاء)$') } | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $Report
                if ($name -match '^(Terminer|Finish|Fermer|إنهاء)$') { exit 0 }
                Start-Sleep -Milliseconds 800
                break
            }
        } catch { continue }
    }
    Start-Sleep -Milliseconds 300
}
@{ buttons=$clicked; finished=$false; timedOut=$true } | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $Report
exit 1
