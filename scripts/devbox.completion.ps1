# PowerShell tab completion for devbox
# Add to your $PROFILE:
#   . /path/to/devbox.completion.ps1

function _Devbox_GetNames {
    if (-not $env:DEVBOX_HOST) { return }
    try {
        & ssh $env:DEVBOX_HOST docker ps -a --filter 'name=devbox-' --format '{{.Names}}' 2>$null |
            ForEach-Object { $_ -replace '^devbox-', '' } |
            Where-Object { $_ -ne '' }
    } catch { }
}

Register-ArgumentCompleter -Native -CommandName @('devbox', 'devbox.ps1') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $subcommands = @(
        [System.Management.Automation.CompletionResult]::new('list',    'list',    'ParameterValue', 'List all devboxes and their status')
        [System.Management.Automation.CompletionResult]::new('ls',      'ls',      'ParameterValue', 'Alias for list')
        [System.Management.Automation.CompletionResult]::new('create',  'create',  'ParameterValue', 'Create a new devbox (or resume if stopped)')
        [System.Management.Automation.CompletionResult]::new('start',   'start',   'ParameterValue', 'Resume a stopped devbox')
        [System.Management.Automation.CompletionResult]::new('stop',    'stop',    'ParameterValue', 'Stop a running devbox')
        [System.Management.Automation.CompletionResult]::new('destroy', 'destroy', 'ParameterValue', 'Remove a devbox container (data preserved)')
        [System.Management.Automation.CompletionResult]::new('share',   'share',   'ParameterValue', 'Expose a devbox publicly via Cloudflare Tunnel')
        [System.Management.Automation.CompletionResult]::new('unshare', 'unshare', 'ParameterValue', 'Stop the Cloudflare Tunnel')
        [System.Management.Automation.CompletionResult]::new('pin',     'pin',     'ParameterValue', 'Toggle pin state (pinned devboxes never auto-stop)')
        [System.Management.Automation.CompletionResult]::new('upgrade', 'upgrade', 'ParameterValue', 'Upgrade devbox(es) to the current base image')
        [System.Management.Automation.CompletionResult]::new('ssh',     'ssh',     'ParameterValue', 'SSH into a devbox')
        [System.Management.Automation.CompletionResult]::new('code',    'code',    'ParameterValue', 'Open a devbox in VSCode (Remote SSH)')
        [System.Management.Automation.CompletionResult]::new('zed',     'zed',     'ParameterValue', 'Open a devbox in Zed (remote)')
        [System.Management.Automation.CompletionResult]::new('help',    'help',    'ParameterValue', 'Show help for a command')
    )

    $n   = $commandAst.CommandElements.Count
    $sub = if ($n -ge 2) { $commandAst.CommandElements[1].Value } else { '' }

    # Still completing the subcommand itself
    if ($n -le 1 -or ($n -eq 2 -and $wordToComplete -ne '')) {
        return $subcommands | Where-Object { $_.CompletionText -like "$wordToComplete*" }
    }

    switch ($sub) {
        { $_ -in @('start','stop','destroy','unshare','pin','ssh','code','zed') } {
            _Devbox_GetNames | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
        'upgrade' {
            if ($wordToComplete -like '-*') {
                [System.Management.Automation.CompletionResult]::new('--all', '--all', 'ParameterValue', 'Upgrade all devboxes')
            } else {
                _Devbox_GetNames | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            }
        }
        'share' {
            if ($wordToComplete -like '-*') {
                [System.Management.Automation.CompletionResult]::new('--port', '--port', 'ParameterValue', 'Port to forward (default: 3000)')
            } else {
                _Devbox_GetNames | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            }
        }
        'create' {
            $prevToken = if ($wordToComplete -eq '' -and $n -ge 2) {
                $commandAst.CommandElements[$n - 1].Value
            } elseif ($wordToComplete -ne '' -and $n -ge 3) {
                $commandAst.CommandElements[$n - 2].Value
            } else { '' }

            if ($prevToken -eq '--mount') {
                if ($env:DEVBOX_HOST) {
                    try {
                        & ssh $env:DEVBOX_HOST 'source /etc/devbox/config 2>/dev/null; compgen -v DEVBOX_MOUNT_' 2>$null |
                            ForEach-Object { ($_ -replace '^DEVBOX_MOUNT_', '') -replace '_', '-' } |
                            Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                            }
                    } catch { }
                }
            } elseif ($prevToken -notin @('--timeout', '--volume', '-v')) {
                @('--pin', '--timeout', '--volume', '-v', '--mount') |
                    Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
            }
        }
        'help' {
            $subcommands | Where-Object { $_.CompletionText -like "$wordToComplete*" }
        }
    }
}
