#!/usr/bin/env pwsh
# devbox — manage devbox containers (Windows PowerShell client)
# Set DEVBOX_HOST in your environment to point at your devbox server.

$Command  = if ($args.Count -gt 0) { $args[0] } else { '' }
$RestArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

# These commands open local apps and must run on this machine, not the server.
if ($Command -in @('ssh', 'code', 'zed')) {
    if ($RestArgs.Count -eq 0) {
        Write-Host "Usage: devbox $Command <name>"
        exit 1
    }
    $Name  = $RestArgs[0]
    $Extra = if ($RestArgs.Count -gt 1) { $RestArgs[1..($RestArgs.Count - 1)] } else { @() }

    switch ($Command) {
        'ssh' {
            ssh-keygen -R $Name 2>&1 | Out-Null
            & ssh -tt -A -o StrictHostKeyChecking=accept-new "$env:USERNAME@$Name" @Extra
        }
        'code' { & code --remote "ssh-remote+$env:USERNAME@$Name" /workspace }
        'zed'  { & zed "ssh://$env:USERNAME@$Name/workspace" }
    }
    exit $LASTEXITCODE
}

if (-not $env:DEVBOX_HOST) {
    Write-Host 'Error: DEVBOX_HOST is not set.' -ForegroundColor Red
    Write-Host "  Set for this session:  `$env:DEVBOX_HOST = 'ds9'"
    Write-Host '  Or add to your $PROFILE for persistence.'
    exit 1
}

if ($Command -eq '') {
    & ssh $env:DEVBOX_HOST devbox
} else {
    & ssh $env:DEVBOX_HOST devbox $Command @RestArgs
}
exit $LASTEXITCODE
