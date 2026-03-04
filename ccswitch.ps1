#!/usr/bin/env pwsh
# ccswitch.ps1 - cc-switch 数据迁移模块
#Requires -Version 7.0

# 注意：此模块需要由 cc.ps1 在定义 $script:PROFILES_DIR 之后 dot-source 导入

# 从名称生成别名
function Get-AliasFromName {
    param([string]$Name)

    # 转小写，替换空格为连字符，移除非法字符
    $alias = $Name.ToLower()
    $alias = $alias -replace '\s+', '-'
    $alias = $alias -replace '[^a-z0-9-]', ''
    return $alias
}

# 从 cc-switch 数据库读取配置
function Get-CcSwitchConfigs {
    $dbPath = "$env:USERPROFILE/.cc-switch/cc-switch.db"

    if (-not (Test-Path $dbPath)) {
        return $null
    }

    # 使用 sqlite3 查询
    $query = "SELECT name, settings_config, is_current FROM providers WHERE app_type='claude'"
    $result = sqlite3 $dbPath $query 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $configs = @()
    foreach ($line in $result) {
        # 解析管道分隔的输出
        $parts = $line -split '\|'
        if ($parts.Count -ge 2) {
            $name = $parts[0]
            $settingsJson = $parts[1]
            $isCurrent = ($parts.Count -ge 3 -and $parts[2] -eq '1')

            try {
                $settings = $settingsJson | ConvertFrom-Json
                $alias = Get-AliasFromName -Name $name

                $configs += @{
                    alias = $alias
                    name = $name
                    isCurrent = $isCurrent
                    env = $settings.env
                }
            }
            catch {
                # 跳过解析失败的配置
            }
        }
    }

    return $configs
}

# 从 cc-switch 迁移配置
function Import-FromCcSwitch {
    $dbPath = "$env:USERPROFILE/.cc-switch/cc-switch.db"

    # 检查数据库是否存在
    if (-not (Test-Path $dbPath)) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 未找到 cc-switch 数据库" -ForegroundColor Red
        Write-Host "  路径: $dbPath"
        Write-Host ""
        return
    }

    # 读取配置
    Write-Host ""
    Write-Host "正在读取 cc-switch 数据库..." -ForegroundColor Cyan
    $configs = Get-CcSwitchConfigs

    if ($null -eq $configs -or $configs.Count -eq 0) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 未找到可迁移的配置" -ForegroundColor Red
        Write-Host ""
        return
    }

    # 显示多选界面
    $selected = Show-MultiSelectSelector -Items $configs -Title "从 cc-switch 导入配置"

    if ($null -eq $selected) {
        Write-Host ""
        Write-Host "已取消" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    if ($selected.Count -eq 0) {
        Write-Host ""
        Write-Host "未选择任何配置" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # 导入选中的配置
    $imported = @()
    $skipped = @()
    $overwritten = @()

    foreach ($config in $selected) {
        $profilePath = "$script:PROFILES_DIR/$($config.alias).json"
        $shouldWrite = $true
        $isOverwrite = $false

        # 检查是否已存在
        if (Test-Path $profilePath) {
            Write-Host ""
            Write-Host "配置 '$($config.alias)' 已存在，是否覆盖？ (y/N): " -NoNewline -ForegroundColor Yellow
            $confirm = Read-Host

            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                $shouldWrite = $false
                $skipped += $config.alias
            } else {
                $isOverwrite = $true
            }
        }

        if ($shouldWrite) {
            # 构建配置对象
            $newConfig = @{
                name = $config.name
                env = $config.env
                skipDangerousModePermissionPrompt = $true
            }

            # 保存配置
            $newConfig | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

            if ($isOverwrite) {
                $overwritten += $config.alias
            } else {
                $imported += $config.alias
            }
        }
    }

    # 显示结果
    Write-Host ""
    Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 导入完成" -ForegroundColor Green

    if ($imported.Count -gt 0) {
        Write-Host "  新增: $($imported -join ', ')" -ForegroundColor Green
    }
    if ($overwritten.Count -gt 0) {
        Write-Host "  覆盖: $($overwritten -join ', ')" -ForegroundColor Yellow
    }
    if ($skipped.Count -gt 0) {
        Write-Host "  跳过: $($skipped -join ', ')" -ForegroundColor DarkGray
    }

    Write-Host ""
}
