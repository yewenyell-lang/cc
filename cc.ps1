#!/usr/bin/env pwsh
# cc.ps1 - Claude Code 配置管理工具

#Requires -Version 7.0

# 导入 TUI 模块
. "$PSScriptRoot/tui.ps1"

# 配置目录
$script:CC_DIR = "$env:USERPROFILE/.cc"
$script:PROFILES_DIR = "$script:CC_DIR/profiles"
$script:CURRENT_FILE = "$script:CC_DIR/current"

# 确保配置目录存在
function Ensure-ConfigDir {
    if (-not (Test-Path $script:PROFILES_DIR)) {
        New-Item -ItemType Directory -Path $script:PROFILES_DIR -Force | Out-Null
    }
}

# 获取所有配置
function Get-Profiles {
    param([string]$CurrentAlias)

    $profiles = @()
    foreach ($file in Get-ChildItem "$script:PROFILES_DIR/*.json" -ErrorAction SilentlyContinue) {
        try {
            $config = Get-Content $file.FullName | ConvertFrom-Json
            $profiles += @{
                alias = $file.BaseName
                name = $config.name
                isCurrent = ($file.BaseName -eq $CurrentAlias)
                config = $config
            }
        }
        catch {
            Write-Warning "配置文件损坏: $($file.Name)"
        }
    }
    return $profiles
}

# 获取当前配置别名
function Get-CurrentAlias {
    if (Test-Path $script:CURRENT_FILE) {
        return Get-Content $script:CURRENT_FILE -ErrorAction SilentlyContinue
    }
    return $null
}

# 设置当前配置
function Set-CurrentAlias {
    param([string]$Alias)
    Set-Content -Path $script:CURRENT_FILE -Value $Alias -Force
}

# 显示帮助信息
function Show-Help {
    $currentAlias = Get-CurrentAlias
    $currentProfile = $null

    if ($currentAlias) {
        $profilePath = "$script:PROFILES_DIR/$currentAlias.json"
        if (Test-Path $profilePath) {
            $currentProfile = Get-Content $profilePath | ConvertFrom-Json
        }
    }

    Write-Host ""
    Write-Host "Claude Code 配置管理工具" -ForegroundColor Cyan
    Write-Host ""

    if ($currentProfile) {
        Write-Host "当前配置: $currentAlias ($($currentProfile.name))" -ForegroundColor Green
        Write-Host "Base URL: $($currentProfile.env.ANTHROPIC_BASE_URL)"
        Write-Host "模型: $($currentProfile.env.ANTHROPIC_MODEL)"
    } else {
        Write-Host "当前配置: 无" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "命令:"
    Write-Host "  cc use [alias]  切换配置并启动 Claude Code (无参数显示选择器)"
    Write-Host "  cc list         列出所有配置"
    Write-Host "  cc new          创建新配置"
    Write-Host "  cc edit [alias] 编辑配置 (无参数显示选择器)"
    Write-Host "  cc rm [alias]   删除配置 (无参数显示选择器)"
    Write-Host "  cc test [alias] 测试 API 连接 (无参数显示选择器)"
    Write-Host ""
}

# 显示配置列表
function Show-List {
    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias

    Write-Host ""
    Write-Host "配置列表 ($($profiles.Count) 个)" -ForegroundColor Cyan
    Write-Host ""

    if ($profiles.Count -eq 0) {
        Write-Host "  暂无配置，使用 cc new 创建" -ForegroundColor Yellow
        return
    }

    # 表头
    Write-Host "  别名          显示名称              模型"
    Write-Host "  " -NoNewline
    Write-Host ("─" * 50) -ForegroundColor DarkGray

    foreach ($p in $profiles) {
        $marker = if ($p.isCurrent) { "$($ANSI.Green)●$($ANSI.Reset)" } else { " " }
        $alias = $p.alias.PadRight(12)
        $name = $p.name.PadRight(16)
        $model = $p.config.env.ANTHROPIC_MODEL

        Write-Host "  $marker $alias $name $model"
    }

    Write-Host ""
    Write-Host "  ● 当前使用的配置" -ForegroundColor DarkGray
    Write-Host ""
}

# 创建新配置
function New-Profile {
    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias
    $existingAliases = $profiles | ForEach-Object { $_.alias }

    $result = Show-ConfigForm -ExistingAliases $existingAliases

    if ($result) {
        # 保存配置文件
        $profilePath = "$script:PROFILES_DIR/$($result.alias).json"
        $result | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$($result.alias)' 创建成功" -ForegroundColor Green
        Write-Host ""
    }
}

# 主入口
Ensure-ConfigDir

$command = $args[0]
$param = $args[1]

switch ($command) {
    $null { Show-Help }
    'use' { Write-Host "use 命令 - 待实现" }
    'list' { Show-List }
    'new' { New-Profile }
    'edit' { Write-Host "edit 命令 - 待实现" }
    'rm' { Write-Host "rm 命令 - 待实现" }
    'test' { Write-Host "test 命令 - 待实现" }
    default { Write-Host "未知命令: $command" -ForegroundColor Red; Show-Help }
}
