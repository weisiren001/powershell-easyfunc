& {
    # Wrapped in script block for pipe execution compatibility
    $ErrorActionPreference = 'Stop'
    
    $remoteUrl = 'https://raw.githubusercontent.com/weisiren001/powershell-easyfunc/main/easyfunc.ps1'
    $startTag = '# <<<EASYFUNC_MANAGED_BLOCK_BEGIN_DO_NOT_EDIT_MANUALLY>>>'
    $endTag = '# <<<EASYFUNC_MANAGED_BLOCK_END>>>'
    
    Write-Host ''
    Write-Host 'PowerShell EasyFunc - Web Installation' -ForegroundColor Cyan
    Write-Host ''
    
    # Download easyfunc.ps1
    Write-Host 'Downloading function definitions...' -ForegroundColor Cyan
    $tempFile = Join-Path $env:TEMP "easyfunc_$(Get-Random).ps1"
    Invoke-WebRequest -Uri $remoteUrl -OutFile $tempFile -UseBasicParsing
    Write-Host "Downloaded to: $tempFile" -ForegroundColor Green
    
    # Extract function block
    $sourceContent = Get-Content -LiteralPath $tempFile -Raw
    $startIndex = $sourceContent.IndexOf($startTag)
    $endIndex = $sourceContent.IndexOf($endTag, $startIndex) + $endTag.Length
    $block = $sourceContent.Substring($startIndex, $endIndex - $startIndex).TrimEnd() + "`r`n"
    
    # Get candidate profiles
    $candidates = @()
    $addedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    
    $profileMap = @{
        'CurrentUserCurrentHost' = $PROFILE
        'CurrentUserAllHosts' = $PROFILE.CurrentUserAllHosts
        'AllUsersCurrentHost' = $PROFILE.AllUsersCurrentHost
        'AllUsersAllHosts' = $PROFILE.AllUsersAllHosts
    }
    
    foreach ($entry in $profileMap.GetEnumerator()) {
        if ($entry.Value -and $addedPaths.Add($entry.Value)) {
            $candidates += [PSCustomObject]@{
                Name = $entry.Key
                Path = $entry.Value
                Exists = Test-Path -LiteralPath $entry.Value
            }
        }
    }
    
    if ($candidates.Count -eq 0) {
        Write-Host 'ERROR: No profiles available' -ForegroundColor Red
        return
    }
    
    # Interactive profile selection
    $selected = @()
    
    while ($true) {
        Write-Host ''
        Write-Host '==== Select Profile ====' -ForegroundColor Yellow
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            $index = $i + 1
            $profile = $candidates[$i]
            $marker = if ($selected -contains $index) { 'x' } else { ' ' }
            $status = if ($profile.Exists) { 'exists' } else { 'new' }
            Write-Host ("{0,2}. [{1}] {2} -> {3} ({4})" -f $index, $marker, $profile.Name, $profile.Path, $status)
        }
        Write-Host ''
        Write-Host 'Input: number(s) to toggle (e.g. 1,2), A=all, N=none, C=confirm, Q=quit' -ForegroundColor Cyan
        
        $input = (Read-Host 'Choice').Trim()
        
        if (-not $input) {
            continue
        }
        
        switch ($input.ToLower()) {
            'a' {
                $selected = 1..$candidates.Count
                continue
            }
            'n' {
                $selected = @()
                continue
            }
            'c' {
                if ($selected.Count -eq 0) {
                    Write-Host 'No profile selected!' -ForegroundColor Yellow
                    continue
                }
                break
            }
            'q' {
                Write-Host 'Cancelled'
                return
            }
            default {
                $parts = $input -split '[,\s]+' | Where-Object { $_ }
                $valid = $true
                foreach ($part in $parts) {
                    $number = 0
                    if (-not [int]::TryParse($part, [ref]$number)) {
                        Write-Host "Invalid input: $part" -ForegroundColor Yellow
                        $valid = $false
                        break
                    }
                    if ($number -lt 1 -or $number -gt $candidates.Count) {
                        Write-Host "Out of range: $number" -ForegroundColor Yellow
                        $valid = $false
                        break
                    }
                    if ($selected -contains $number) {
                        $selected = $selected | Where-Object { $_ -ne $number }
                    } else {
                        $selected += $number
                    }
                }
                if ($valid) {
                    continue
                }
            }
        }
        break
    }
    
    # Install to selected profiles
    $targets = $selected | Sort-Object -Unique | ForEach-Object { $candidates[$_ - 1] }
    
    Write-Host ''
    Write-Host 'Installing...' -ForegroundColor Cyan
    
    foreach ($profile in $targets) {
        try {
            $profilePath = $profile.Path
            $profileDir = Split-Path -Path $profilePath -Parent
            
            if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            }
            
            $profileContent = if (Test-Path -LiteralPath $profilePath) {
                Get-Content -LiteralPath $profilePath -Raw
            } else {
                ''
            }
            
            if ([string]::IsNullOrEmpty($profileContent)) {
                $profileContent = ''
            }
            
            $pStartIndex = $profileContent.IndexOf($startTag)
            
            if ($pStartIndex -ge 0) {
                $pEndIndex = $profileContent.IndexOf($endTag, $pStartIndex) + $endTag.Length
                $updated = $profileContent.Substring(0, $pStartIndex) + $block + $profileContent.Substring($pEndIndex)
                $action = 'updated'
            } else {
                $separator = if ([string]::IsNullOrWhiteSpace($profileContent) -or $profileContent.EndsWith("`n") -or $profileContent.EndsWith("`r")) {
                    ''
                } else {
                    "`r`n`r`n"
                }
                $updated = $profileContent + $separator + $block
                $action = 'added'
            }
            
            Set-Content -LiteralPath $profilePath -Value $updated -Encoding UTF8 -NoNewline
            Write-Host "OK [$($profile.Path)] $action" -ForegroundColor Green
        } catch {
            Write-Host "ERROR [$($profile.Path)]: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host ''
    Write-Host 'Installation complete!' -ForegroundColor Green
    Write-Host 'Reload your profile with: . $PROFILE' -ForegroundColor Cyan
    
    # Cleanup
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
}
