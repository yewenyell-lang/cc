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
    Write-Host "  cc list, ls     列出所有配置"
    Write-Host "  cc new          创建新配置"
    Write-Host "  cc edit [alias] 编辑配置 (无参数显示选择器)"
    Write-Host "  cc rm [alias]   删除配置 (无参数显示选择器)"
    Write-Host "  cc test [alias] 测试 API 连接 (无参数显示选择器)"
    Write-Host "  cc ccswitch     从 cc-switch 迁移配置"
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
        $currentMark = if ($p.isCurrent) { "$($ANSI.Green)(当前)$($ANSI.Reset)" } else { "" }
        $alias = $p.alias.PadRight(12)
        $name = $p.name.PadRight(16)
        $model = $p.config.env.ANTHROPIC_MODEL

        Write-Host "  $alias $name $model $currentMark"
    }

    Write-Host ""
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

# 切换配置并启动 Claude Code
function Use-Profile {
    param([string]$Alias)

    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias

    # 无参数时显示选择器
    if (-not $Alias) {
        if ($profiles.Count -eq 0) {
            Write-Host ""
            Write-Host "暂无配置，使用 cc new 创建" -ForegroundColor Yellow
            Write-Host ""
            return
        }

        $Alias = Show-ProfileSelector -Profiles $profiles -Title "选择配置"
        if (-not $Alias) {
            return
        }
    }

    # 验证配置存在
    $profilePath = "$script:PROFILES_DIR/$Alias.json"
    if (-not (Test-Path $profilePath)) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 配置 '$Alias' 不存在" -ForegroundColor Red
        Write-Host ""
        return
    }

    # 读取配置
    $config = Get-Content $profilePath | ConvertFrom-Json

    # 注入固定字段
    $config.env | Add-Member -NotePropertyName "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" -NotePropertyValue "1" -Force

    # 生成临时配置文件
    $tempPath = [System.IO.Path]::GetTempFileName() + ".json"
    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8

        # 更新当前配置
        Set-CurrentAlias -Alias $Alias

        # 启动 Claude Code
        Write-Host ""
        Write-Host "启动 Claude Code (配置: $Alias)..." -ForegroundColor Cyan
        & claude --settings $tempPath
    }
    finally {
        # 清理临时文件
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# 编辑配置
function Edit-Profile {
    param([string]$Alias)

    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias

    # 无参数时显示选择器
    if (-not $Alias) {
        if ($profiles.Count -eq 0) {
            Write-Host ""
            Write-Host "暂无配置，使用 cc new 创建" -ForegroundColor Yellow
            Write-Host ""
            return
        }

        $Alias = Show-ProfileSelector -Profiles $profiles -Title "选择要编辑的配置"
        if (-not $Alias) {
            return
        }
    }

    # 验证配置存在
    $profilePath = "$script:PROFILES_DIR/$Alias.json"
    if (-not (Test-Path $profilePath)) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 配置 '$Alias' 不存在" -ForegroundColor Red
        Write-Host ""
        return
    }

    # 读取现有配置
    $existingConfig = Get-Content $profilePath | ConvertFrom-Json
    $existingHashtable = @{
        alias = $Alias
        name = $existingConfig.name
        env = @{
            ANTHROPIC_AUTH_TOKEN = $existingConfig.env.ANTHROPIC_AUTH_TOKEN
            ANTHROPIC_BASE_URL = $existingConfig.env.ANTHROPIC_BASE_URL
            ANTHROPIC_MODEL = $existingConfig.env.ANTHROPIC_MODEL
            ANTHROPIC_DEFAULT_SONNET_MODEL = $existingConfig.env.ANTHROPIC_DEFAULT_SONNET_MODEL
            ANTHROPIC_DEFAULT_OPUS_MODEL = $existingConfig.env.ANTHROPIC_DEFAULT_OPUS_MODEL
            ANTHROPIC_DEFAULT_HAIKU_MODEL = $existingConfig.env.ANTHROPIC_DEFAULT_HAIKU_MODEL
            ANTHROPIC_REASONING_MODEL = $existingConfig.env.ANTHROPIC_REASONING_MODEL
        }
    }

    $existingAliases = $profiles | ForEach-Object { $_.alias }
    $result = Show-ConfigForm -ExistingConfig $existingHashtable -IsEdit -ExistingAliases $existingAliases

    if ($result) {
        # 保存配置（使用原别名）
        $result.alias = $Alias
        $result | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$Alias' 已更新" -ForegroundColor Green
        Write-Host ""
    }
}

# 删除配置
function Remove-Profile {
    param([string]$Alias)

    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias

    # 无参数时显示选择器
    if (-not $Alias) {
        if ($profiles.Count -eq 0) {
            Write-Host ""
            Write-Host "暂无配置" -ForegroundColor Yellow
            Write-Host ""
            return
        }

        $Alias = Show-ProfileSelector -Profiles $profiles -Title "选择要删除的配置"
        if (-not $Alias) {
            return
        }
    }

    # 验证配置存在
    $profilePath = "$script:PROFILES_DIR/$Alias.json"
    if (-not (Test-Path $profilePath)) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 配置 '$Alias' 不存在" -ForegroundColor Red
        Write-Host ""
        return
    }

    # 确认删除
    Write-Host ""
    Write-Host "确定要删除配置 '$Alias' 吗？ (y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host

    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Remove-Item $profilePath -Force

        # 如果删除的是当前配置，清除 current 文件
        if ($Alias -eq $currentAlias) {
            Remove-Item $script:CURRENT_FILE -Force -ErrorAction SilentlyContinue
        }

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$Alias' 已删除" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "已取消" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# 测试 API 连接
function Test-ApiConnection {
    param([string]$BaseUrl, [string]$Token)

    $startTime = Get-Date

    try {
        $headers = @{
            "x-api-key" = $Token
            "Content-Type" = "application/json"
            "anthropic-version" = "2023-06-01"
        }

        $body = @{
            model = "claude-3-haiku-20240307"
            max_tokens = 10
            messages = @(@{
                role = "user"
                content = "Hi"
            })
        } | ConvertTo-Json -Depth 3

        $response = Invoke-RestMethod `
            -Uri "$BaseUrl/v1/messages" `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -TimeoutSec 10

        $elapsed = ((Get-Date) - $startTime).TotalMilliseconds

        return @{
            Success = $true
            Latency = [math]::Round($elapsed, 0)
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__

        # 获取完整错误信息
        $fullError = $_.Exception.Message
        if ($_.Exception.InnerException) {
            $fullError += " -> $($_.Exception.InnerException.Message)"
        }

        # 尝试读取响应体
        $responseBody = $null
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
            } catch {}
        }

        $errorMsg = switch ($statusCode) {
            401 { "认证失败，请检查令牌" }
            403 { "访问被拒绝" }
            404 { "API 端点不存在" }
            500 { "服务器内部错误" }
            default { "连接失败: $fullError" }
        }

        return @{
            Success = $false
            Message = $errorMsg
            Details = if ($responseBody) { $responseBody } else { $fullError }
            Request = @{
                Url = "$BaseUrl/v1/messages"
                Headers = @{
                    "x-api-key" = "****" + $Token.Substring([Math]::Max(0, $Token.Length - 4))
                    "Content-Type" = "application/json"
                    "anthropic-version" = "2023-06-01"
                }
                Body = $body
            }
        }
    }
}

# 测试配置
function Test-Profile {
    param([string]$Alias)

    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias

    # 无参数时显示选择器
    if (-not $Alias) {
        if ($profiles.Count -eq 0) {
            Write-Host ""
            Write-Host "暂无配置，使用 cc new 创建" -ForegroundColor Yellow
            Write-Host ""
            return
        }

        $Alias = Show-ProfileSelector -Profiles $profiles -Title "选择要测试的配置"
        if (-not $Alias) {
            return
        }
    }

    # 验证配置存在
    $profilePath = "$script:PROFILES_DIR/$Alias.json"
    if (-not (Test-Path $profilePath)) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 配置 '$Alias' 不存在" -ForegroundColor Red
        Write-Host ""
        return
    }

    $config = Get-Content $profilePath | ConvertFrom-Json

    Write-Host ""
    Write-Host "测试配置: $Alias ($($config.name))"
    Write-Host ""
    Write-Host "  API 地址: $($config.env.ANTHROPIC_BASE_URL)"
    Write-Host "  模型: $($config.env.ANTHROPIC_MODEL)"
    Write-Host ""
    Write-Host "  正在连接..." -NoNewline

    $result = Test-ApiConnection `
        -BaseUrl $config.env.ANTHROPIC_BASE_URL `
        -Token $config.env.ANTHROPIC_AUTH_TOKEN

    Write-Host "`r  " -NoNewline  # 清除 "正在连接..."
    Write-Host ""

    if ($result.Success) {
        Write-Host "  ┌────────────────────────────────────────┐" -ForegroundColor Green
        Write-Host "  │$($ANSI.Green)  ✓ 连接成功$($ANSI.Reset)                            │"
        Write-Host "  │    响应时间: $($result.Latency)ms                      │" -ForegroundColor DarkGray
        Write-Host "  └────────────────────────────────────────┘" -ForegroundColor Green
    } else {
        Write-Host "  ┌────────────────────────────────────────┐" -ForegroundColor Red
        Write-Host "  │$($ANSI.BrightRed)  ✗ 连接失败$($ANSI.Reset)                            │"
        Write-Host "  │    $($result.Message)" -ForegroundColor DarkGray
        Write-Host "  └────────────────────────────────────────┘" -ForegroundColor Red

        # 显示请求信息
        if ($result.Request) {
            Write-Host ""
            Write-Host "  请求信息:" -ForegroundColor Cyan
            Write-Host "    URL: $($result.Request.Url)" -ForegroundColor DarkGray
            Write-Host "    Headers:" -ForegroundColor DarkGray
            foreach ($key in $result.Request.Headers.Keys) {
                Write-Host "      ${key}: $($result.Request.Headers[$key])" -ForegroundColor DarkGray
            }
            Write-Host "    Body:" -ForegroundColor DarkGray
            # 格式化 JSON 显示
            $bodyLines = $result.Request.Body -split "`n"
            foreach ($line in $bodyLines) {
                Write-Host "      $line" -ForegroundColor DarkGray
            }
        }

        if ($result.Details) {
            Write-Host ""
            Write-Host "  响应信息:" -ForegroundColor Cyan
            Write-Host "  $($result.Details)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
}

# 主入口
Ensure-ConfigDir

$command = $args[0]
$param = $args[1]

switch ($command) {
    $null { Show-Help }
    'use' { Use-Profile -Alias $param }
    { $_ -in 'list', 'ls' } { Show-List }
    'new' { New-Profile }
    'edit' { Edit-Profile -Alias $param }
    'rm' { Remove-Profile -Alias $param }
    'test' { Test-Profile -Alias $param }
    'ccswitch' { Import-FromCcSwitch }
    default { Write-Host "未知命令: $command" -ForegroundColor Red; Show-Help }
}
