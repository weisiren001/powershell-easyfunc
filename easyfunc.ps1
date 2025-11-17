<#
MIT License
Copyright (c) 2025 Chen Xuanyi

This file is part of powershell-easyfunc and is released under the MIT License.
See the LICENSE file in the project root for details.
#>

# <<<EASYFUNC_MANAGED_BLOCK_BEGIN_DO_NOT_EDIT_MANUALLY>>>
function wr {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $Patterns
    )
    where.exe @Patterns
}

Set-Alias wrs wr

function open {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Targets
    )

    if (-not $Targets -or $Targets.Count -eq 0) {
        $Targets = @('.')
    }

    foreach ($target in $Targets) {
        if ([string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        $resolvedPath = $target
        $exists = $false
        $isDirectory = $false

        if (Test-Path -LiteralPath $target) {
            try {
                $resolvedPath = (Resolve-Path -LiteralPath $target).ProviderPath
                $exists = $true
                $isDirectory = (Get-Item -LiteralPath $resolvedPath).PSIsContainer
            } catch {
                $resolvedPath = $target
            }
        }

        try {
            if ($exists -and $isDirectory) {
                Start-Process explorer.exe -ArgumentList "`"$resolvedPath`""
            } else {
                Start-Process -FilePath $resolvedPath
            }
        } catch {
            Write-Error "无法打开 '$target': $($_.Exception.Message)"
        }
    }
}

# <<<EASYFUNC_MANAGED_BLOCK_END>>>
