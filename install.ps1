param(
    [string]$SourceFile = (Join-Path $PSScriptRoot 'easyfunc.ps1'),
    [string]$RemoteUrl = 'https://raw.githubusercontent.com/weisiren001/powershell-easyfunc/main/easyfunc.ps1'
)

$startTag = '# <<<EASYFUNC_MANAGED_BLOCK_BEGIN_DO_NOT_EDIT_MANUALLY>>>'
$endTag = '# <<<EASYFUNC_MANAGED_BLOCK_END>>>'

# 如果本地源文件不存在，尝试从远程 URL 下载
if (-not (Test-Path -LiteralPath $SourceFile)) {
    Write-Host '本地源文件不存在，尝试从远程获取...' -ForegroundColor Cyan
    try {
        $tempFile = Join-Path $env:TEMP "easyfunc_$(Get-Random).ps1"
        Invoke-WebRequest -Uri $RemoteUrl -OutFile $tempFile -UseBasicParsing
        $SourceFile = $tempFile
        Write-Host "已从远程下载到临时文件：$tempFile" -ForegroundColor Green
    } catch {
        throw "无法从远程 URL 下载源文件：$($_.Exception.Message)"
    }
}

function Get-EasyFuncBlock {
    param(
        [string]$SourcePath,
        [string]$StartTag,
        [string]$EndTag
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "找不到来源脚本：$SourcePath"
    }

    $sourceContent = Get-Content -LiteralPath $SourcePath -Raw
    $startIndex = $sourceContent.IndexOf($StartTag)
    
    if ($startIndex -lt 0) {
        throw "来源脚本中没有找到开始标签：$StartTag"
    }

    $endIndex = $sourceContent.IndexOf($EndTag, $startIndex)
    if ($endIndex -lt 0) {
        throw "来源脚本中没有找到结束标签：$EndTag"
    }

    $endIndex += $EndTag.Length
    $block = $sourceContent.Substring($startIndex, $endIndex - $startIndex)
    return $block.TrimEnd() + "`r`n"
}

function Get-CandidateProfiles {
    param(
        [string]$DefaultProfile
    )

    $candidates = @()
    $addedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $profileMap = [ordered]@{
        'CurrentUserCurrentHost' = $PROFILE
        'CurrentUserAllHosts'    = $PROFILE.CurrentUserAllHosts
        'AllUsersCurrentHost'    = $PROFILE.AllUsersCurrentHost
        'AllUsersAllHosts'       = $PROFILE.AllUsersAllHosts
    }

    foreach ($entry in $profileMap.GetEnumerator()) {
        $path = $entry.Value
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        if ($addedPaths.Add($path)) {
            $candidates += [pscustomobject]@{
                Name   = $entry.Key
                Path   = $path
                Exists = Test-Path -LiteralPath $path
            }
        }
    }

    $profileDir = Split-Path -Path $DefaultProfile -Parent
    if ($profileDir -and (Test-Path -LiteralPath $profileDir)) {
        Get-ChildItem -LiteralPath $profileDir -Filter '*profile*.ps1' -File | ForEach-Object {
            if ($addedPaths.Add($_.FullName)) {
                $candidates += [pscustomobject]@{
                    Name   = "Existing: $($_.Name)"
                    Path   = $_.FullName
                    Exists = $true
                }
            }
        }
    }

    return $candidates
}

function Test-IsAdministrator {
    try {
        $current = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object 'Security.Principal.WindowsPrincipal' $current
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Show-ProfileMenu {
    param(
        [array]$Profiles,
        $Selected
    )

    Write-Host ''
    Write-Host '==== Profile 选择 ===='
    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $index = $i + 1
        $profile = $Profiles[$i]
        $marker = if ($Selected -contains $index) { 'x' } else { ' ' }
        $status = if ($profile.Exists) { '存在' } else { '新建' }
        Write-Host ("{0,2}. [{1}] {2} -> {3} ({4})" -f $index, $marker, $profile.Name, $profile.Path, $status)
    }
    Write-Host ''
    Write-Host '输入：数字切换选择 (可多个，例如 1,3,5)，A=全选，N=清空，C=确认，Q=取消退出。'
}

function Install-EasyFuncBlock {
    param(
        [string]$ProfilePath,
        [string]$Block,
        [string]$StartTag,
        [string]$EndTag
    )

    $profileDir = Split-Path -Path $ProfilePath -Parent
    if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    $profileContent = if (Test-Path -LiteralPath $ProfilePath) {
        Get-Content -LiteralPath $ProfilePath -Raw
    } else {
        ''
    }

    if ([string]::IsNullOrEmpty($profileContent)) {
        $profileContent = ''
    }

    $startIndex = $profileContent.IndexOf($StartTag)
    
    if ($startIndex -ge 0) {
        $endIndex = $profileContent.IndexOf($EndTag, $startIndex)
        if ($endIndex -ge 0) {
            $endIndex += $EndTag.Length
            $before = $profileContent.Substring(0, $startIndex)
            $after = $profileContent.Substring($endIndex)
            $updated = $before + $Block + $after
            $action = '更新'
        } else {
            throw "在 Profile 中找到了开始标签但没有找到结束标签，文件可能已损坏"
        }
    } else {
        $separator = if ([string]::IsNullOrWhiteSpace($profileContent) -or $profileContent.EndsWith("`n") -or $profileContent.EndsWith("`r")) {
            ''
        } else {
            "`r`n`r`n"
        }
        $updated = $profileContent + $separator + $Block
        $action = '新增'
    }

    Set-Content -LiteralPath $ProfilePath -Value $updated -Encoding UTF8 -NoNewline
    return $action
}

function Uninstall-EasyFuncBlock {
    param(
        [string]$ProfilePath,
        [string]$StartTag,
        [string]$EndTag
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        return $false
    }

    $profileContent = Get-Content -LiteralPath $ProfilePath -Raw
    if ([string]::IsNullOrEmpty($profileContent)) {
        return $false
    }

    $startIndex = $profileContent.IndexOf($StartTag)
    if ($startIndex -lt 0) {
        return $false
    }

    $endIndex = $profileContent.IndexOf($EndTag, $startIndex)
    if ($endIndex -lt 0) {
        throw "在 Profile 中找到了开始标签但没有找到结束标签，文件可能已损坏"
    }

    $endIndex += $EndTag.Length
    $before = $profileContent.Substring(0, $startIndex)
    $after = $profileContent.Substring($endIndex)
    
    $updated = $before.TrimEnd() + $after.TrimStart()
    if ($updated.Length -gt 0 -and -not $updated.EndsWith("`n")) {
        $updated += "`r`n"
    }

    Set-Content -LiteralPath $ProfilePath -Value $updated -Encoding UTF8 -NoNewline
    return $true
}

$block = Get-EasyFuncBlock -SourcePath $SourceFile -StartTag $startTag -EndTag $endTag
$profiles = Get-CandidateProfiles -DefaultProfile $PROFILE

if (-not $profiles -or $profiles.Count -eq 0) {
    throw '没有可操作的 Profile。'
}

$selected = @()

while ($true) {
    Show-ProfileMenu -Profiles $profiles -Selected $selected
    $input = (Read-Host '请输入指令').Trim()

    if (-not $input) {
        continue
    }

    switch ($input.ToLower()) {
        'a' {
            $selected = 1..$profiles.Count
            continue
        }
        'n' {
            $selected = @()
            continue
        }
        'c' {
            if ($selected.Count -eq 0) {
                Write-Host '尚未选择任何 Profile。' -ForegroundColor Yellow
                continue
            }
            break
        }
        'q' {
            Write-Host '已取消操作。'
            return
        }
        default {
            $parts = $input -split '[,\s]+' | Where-Object { $_ }
            $valid = $true
            foreach ($part in $parts) {
                $number = 0
                if (-not [int]::TryParse($part, [ref]$number)) {
                    Write-Host "无法解析输入：$part" -ForegroundColor Yellow
                    $valid = $false
                    break
                }
                if ($number -lt 1 -or $number -gt $profiles.Count) {
                    Write-Host "超出范围的编号：$number" -ForegroundColor Yellow
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

$action = $null
while (-not $action) {
    $actionInput = (Read-Host '选择动作 (I=安装/更新, U=卸载, Q=取消)').Trim().ToLower()
    switch ($actionInput) {
        'i' { $action = 'install' }
        'u' { $action = 'uninstall' }
        'q' {
            Write-Host '已取消操作。'
            return
        }
        default { Write-Host '请输入 I / U / Q。' -ForegroundColor Yellow }
    }
}

$selectedIndices = $selected | Sort-Object -Unique
$targets = foreach ($index in $selectedIndices) { $profiles[$index - 1] }

$adminTargets = @(
    $targets | Where-Object {
        $env:ProgramFiles -and $_.Path.StartsWith($env:ProgramFiles, [System.StringComparison]::OrdinalIgnoreCase)
    }
)

if ($adminTargets.Count -gt 0 -and -not (Test-IsAdministrator)) {
    Write-Host ''
    Write-Host '检测到以下 Profile 位于 Program Files 目录，修改它们需要管理员权限：'
    foreach ($t in $adminTargets) {
        Write-Host "  - $($t.Path)"
    }

    $choice = (Read-Host '是否以管理员身份重新运行 install.ps1？(Y=是, N=否，Q=取消)').Trim().ToLower()
    if ($choice -in @('y','yes')) {
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) {
            $scriptPath = $MyInvocation.MyCommand.Path
        }

        if (-not $scriptPath -or -not (Test-Path -LiteralPath $scriptPath)) {
            Write-Host '无法确定脚本路径，请手动以管理员身份运行 pwsh .\install.ps1。' -ForegroundColor Yellow
            return
        }

        $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $arg = "-File `"$scriptPath`""
        if ($SourceFile) {
            $arg = "$arg -SourceFile `"$SourceFile`""
        }

        Write-Host '正在请求管理员权限...' -ForegroundColor Cyan
        Start-Process $hostExe -Verb RunAs -ArgumentList $arg | Out-Null
        return
    } elseif ($choice -in @('q','quit','exit')) {
        Write-Host '已取消操作。'
        return
    } else {
        Write-Host '将继续以当前权限执行，位于 Program Files 的 Profile 将被跳过。' -ForegroundColor Yellow
    }
}

foreach ($profile in $targets) {
    try {
        $requiresAdmin = $false
        if ($env:ProgramFiles) {
            if ($profile.Path.StartsWith($env:ProgramFiles, [System.StringComparison]::OrdinalIgnoreCase)) {
                $requiresAdmin = $true
            }
        }

        if ($requiresAdmin -and -not (Test-IsAdministrator)) {
            Write-Host "[$($profile.Path)] 需要管理员权限，已跳过（请以管理员身份运行 install.ps1 再操作）。" -ForegroundColor Yellow
            continue
        }

        if ($action -eq 'install') {
            $result = Install-EasyFuncBlock -ProfilePath $profile.Path -Block $block -StartTag $startTag -EndTag $endTag
            Write-Host "[$($profile.Path)] 已$($result) easyfunc 区块。"
        } else {
            $removed = Uninstall-EasyFuncBlock -ProfilePath $profile.Path -StartTag $startTag -EndTag $endTag
            if ($removed) {
                Write-Host "[$($profile.Path)] 已卸载 easyfunc 区块。"
            } else {
                Write-Host "[$($profile.Path)] 未找到可卸载的 easyfunc 区块。" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Error "处理 $($profile.Path) 时发生错误：$($_.Exception.Message)"
    }
}

Write-Host '完成。'
