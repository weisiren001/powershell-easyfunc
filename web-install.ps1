# Web-based installation bootstrap script
# This script can be piped to iex for direct installation

$remoteUrl = 'https://raw.githubusercontent.com/weisiren001/powershell-easyfunc/main/easyfunc.ps1'
$startTag = '# <<<EASYFUNC_MANAGED_BLOCK_BEGIN_DO_NOT_EDIT_MANUALLY>>>'
$endTag = '# <<<EASYFUNC_MANAGED_BLOCK_END>>>'

Write-Host '🚀 PowerShell EasyFunc 网络安装' -ForegroundColor Cyan
Write-Host ''

# 下载 easyfunc.ps1
Write-Host '📥 正在下载函数定义...' -ForegroundColor Cyan
try {
    $tempFile = Join-Path $env:TEMP "easyfunc_$(Get-Random).ps1"
    Invoke-WebRequest -Uri $remoteUrl -OutFile $tempFile -UseBasicParsing
    Write-Host "✅ 已下载到临时文件：$tempFile" -ForegroundColor Green
} catch {
    Write-Error "❌ 无法从远程 URL 下载源文件：$($_.Exception.Message)"
    return
}

# 读取函数块
$sourceContent = Get-Content -LiteralPath $tempFile -Raw
$startIndex = $sourceContent.IndexOf($startTag)

if ($startIndex -lt 0) {
    Write-Error "❌ 来源脚本中没有找到开始标签"
    return
}

$endIndex = $sourceContent.IndexOf($endTag, $startIndex)
if ($endIndex -lt 0) {
    Write-Error "❌ 来源脚本中没有找到结束标签"
    return
}

$endIndex += $endTag.Length
$block = $sourceContent.Substring($startIndex, $endIndex - $startIndex)
$block = $block.TrimEnd() + "`r`n"

# 获取候选 Profile
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

if ($candidates.Count -eq 0) {
    Write-Error '❌ 没有可操作的 Profile'
    return
}

# 显示菜单
$selected = @()

while ($true) {
    Write-Host ''
    Write-Host '==== Profile 选择 ====' -ForegroundColor Yellow
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $index = $i + 1
        $profile = $candidates[$i]
        $marker = if ($selected -contains $index) { 'x' } else { ' ' }
        $status = if ($profile.Exists) { '存在' } else { '新建' }
        Write-Host ("{0,2}. [{1}] {2} -> {3} ({4})" -f $index, $marker, $profile.Name, $profile.Path, $status)
    }
    Write-Host ''
    Write-Host '输入：数字切换选择 (可多个，例如 1,3)，A=全选，N=清空，C=确认，Q=取消退出。' -ForegroundColor Cyan
    
    $input = (Read-Host '请输入指令').Trim()

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
                Write-Host '⚠️  尚未选择任何 Profile' -ForegroundColor Yellow
                continue
            }
            break
        }
        'q' {
            Write-Host '❌ 已取消操作'
            return
        }
        default {
            $parts = $input -split '[,\s]+' | Where-Object { $_ }
            $valid = $true
            foreach ($part in $parts) {
                $number = 0
                if (-not [int]::TryParse($part, [ref]$number)) {
                    Write-Host "⚠️  无法解析输入：$part" -ForegroundColor Yellow
                    $valid = $false
                    break
                }
                if ($number -lt 1 -or $number -gt $candidates.Count) {
                    Write-Host "⚠️  超出范围的编号：$number" -ForegroundColor Yellow
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

# 安装到选定的 Profile
$selectedIndices = $selected | Sort-Object -Unique
$targets = foreach ($index in $selectedIndices) { $candidates[$index - 1] }

Write-Host ''
Write-Host '📦 开始安装...' -ForegroundColor Cyan

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

        $startIndex = $profileContent.IndexOf($startTag)
        
        if ($startIndex -ge 0) {
            $endIndex = $profileContent.IndexOf($endTag, $startIndex)
            if ($endIndex -ge 0) {
                $endIndex += $endTag.Length
                $before = $profileContent.Substring(0, $startIndex)
                $after = $profileContent.Substring($endIndex)
                $updated = $before + $block + $after
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
            $updated = $profileContent + $separator + $block
            $action = '新增'
        }

        Set-Content -LiteralPath $profilePath -Value $updated -Encoding UTF8 -NoNewline
        Write-Host "✅ [$($profile.Path)] 已$($action) easyfunc 区块" -ForegroundColor Green
    } catch {
        Write-Error "❌ 处理 $($profile.Path) 时发生错误：$($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host '🎉 安装完成！' -ForegroundColor Green
Write-Host '💡 请重新打开 PowerShell 或运行 `. $PROFILE` 以加载新函数' -ForegroundColor Cyan

# 清理临时文件
try {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
} catch {
    # 忽略清理错误
}
