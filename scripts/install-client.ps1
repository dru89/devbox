param(
    [string]$WinBin   = "$env:USERPROFILE\bin",
    [switch]$Uninstall
)

$ScriptsDir = $PSScriptRoot
$RepoRoot   = Split-Path $ScriptsDir -Parent

if ($Uninstall) {
    'devbox', 'devbox.ps1', 'devbox.cmd' | ForEach-Object {
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $WinBin $_)
    }
    Write-Host "Removed devbox."
    exit 0
}

$null = New-Item -ItemType Directory -Force -Path $WinBin
foreach ($file in @('devbox', 'devbox.ps1', 'devbox.cmd')) {
    Copy-Item -Force (Join-Path $ScriptsDir $file) (Join-Path $WinBin $file)
}

Write-Host ""
Write-Host "Installed to ${WinBin}:"
Write-Host "  devbox        (Git Bash)"
Write-Host "  devbox.ps1    (PowerShell)"
Write-Host "  devbox.cmd    (CMD)"
Write-Host ""
Write-Host "Next steps:"
Write-Host ""
Write-Host "  1. Add $env:USERPROFILE\bin to your Windows PATH if not already there."
Write-Host "     In PowerShell (permanent):"
Write-Host '       [Environment]::SetEnvironmentVariable("PATH", "$env:PATH;$env:USERPROFILE\bin", "User")'
Write-Host ""
Write-Host '  2. Set your server in your PowerShell $PROFILE:'
Write-Host '       $env:DEVBOX_HOST = ''ds9'''
Write-Host ""
Write-Host '  3. Enable tab completion in your PowerShell $PROFILE:'
Write-Host "       . $RepoRoot\scripts\devbox.completion.ps1"
Write-Host ""
