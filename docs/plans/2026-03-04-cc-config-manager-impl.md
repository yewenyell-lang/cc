# CC 配置管理工具实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 构建一个 PowerShell TUI 工具，用于管理 Claude Code 的第三方供应商配置，支持配置的增删改查和快速切换启动。

**Architecture:** 两文件架构：`tui.ps1` 提供 TUI 组件（选择器、表单），`cc.ps1` 处理命令解析和业务逻辑。配置存储在 `~/.cc/` 目录。

**Tech Stack:** PowerShell 7+ (ANSI TUI，无外部依赖)

---

## Task 1: 项目初始化与基础设施

**Files:**
- Create: `tui.ps1`
- Create: `~/.cc/profiles/` 目录

**Step 1: 创建 tui.ps1 文件骨架和 ANSI 常量**

```powershell
# tui.ps1 - TUI 模块

#Requires -Version 7.0

# ANSI 转义序列常量
$script:ANSI = @{
    # 光标控制
    CursorUp       = "`e[A"
    CursorDown     = "`e[B"
    CursorRight    = "`e[C"
    CursorLeft     = "`e[D"
    CursorHome     = "`e[H"
    CursorPos      = "`e[{0};{1}H"  # -f row, col
    SaveCursor     = "`e[s"
    RestoreCursor  = "`e[u"
    HideCursor     = "`e[?25l"
    ShowCursor     = "`e[?25h"

    # 清除
    ClearScreen    = "`e[2J"
    ClearLine      = "`e[2K"
    ClearToEnd     = "`e[0K"

    # 样式
    Reset          = "`e[0m"
    Bold           = "`e[1m"
    Dim            = "`e[2m"
    Reverse        = "`e[7m"
    Underline      = "`e[4m"

    # 前景色
    Black          = "`e[30m"
    Red            = "`e[31m"
    Green          = "`e[32m"
    Yellow         = "`e[33m"
    Blue           = "`e[34m"
    Magenta        = "`e[35m"
    Cyan           = "`e[36m"
    White          = "`e[37m"
    BrightBlack    = "`e[90m"
    BrightRed      = "`e[91m"
    BrightGreen    = "`e[92m"
    BrightWhite    = "`e[97m"

    # 背景色
    BgBlack        = "`e[40m"
    BgRed          = "`e[41m"
    BgGreen        = "`e[42m"
    BgYellow       = "`e[43m"
    BgBlue         = "`e[44m"
    BgCyan         = "`e[46m"
    BgWhite        = "`e[47m"
}

# 边框字符
$script:Border = @{
    TL = '╔'  # 左上
    TR = '╗'  # 右上
    BL = '╚'  # 左下
    BR = '╝'  # 右下
    H  = '═'  # 横线
    V  = '║'  # 竖线
    LT = '╠'  # 左T
    RT = '╣'  # 右T
}
```

**Step 2: 添加键盘输入处理函数**

在 `tui.ps1` 末尾添加：

```powershell
# 读取单个按键
function Read-Key {
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    return @{
        Key       = $key.KeyCode
        Character = $key.Character
        Control   = $key.ControlKeyState -band [ConsoleModifiers]::Control
        Alt       = $key.ControlKeyState -band [ConsoleModifiers]::Alt
    }
}

# 检测是否为 Ctrl+某键
function Test-CtrlKey {
    param($key, [string]$char)
    return $key.Control -and [char]$key.Character -eq $char
}
```

**Step 3: 测试基础功能**

运行: `pwsh -File tui.ps1`
预期: 无错误输出（文件只定义常量和函数）

**Step 4: Commit**

```bash
git add tui.ps1
git commit -m "feat: 添加 tui.ps1 基础设施（ANSI 常量和键盘处理）"
```

---

## Task 2: TUI 绘图辅助函数

**Files:**
- Modify: `tui.ps1`

**Step 1: 添加光标和屏幕控制函数**

```powershell
# 移动光标到指定位置 (1-indexed)
function Move-Cursor {
    param([int]$Row, [int]$Col)
    Write-Host ($script:ANSI.CursorPos -f $Row, $Col) -NoNewline
}

# 保存/恢复光标位置
function Save-Cursor { Write-Host $script:ANSI.SaveCursor -NoNewline }
function Restore-Cursor { Write-Host $script:ANSI.RestoreCursor -NoNewline }
function Hide-Cursor { Write-Host $script:ANSI.HideCursor -NoNewline }
function Show-Cursor { Write-Host $script:ANSI.ShowCursor -NoNewline }

# 清屏
function Clear-Screen {
    Write-Host $script:ANSI.ClearScreen -NoNewline
    Move-Cursor 1 1
}

# 清除当前行
function Clear-Line {
    Write-Host $script:ANSI.ClearLine -NoNewline
}
```

**Step 2: 添加边框绘制函数**

```powershell
# 绘制文本行（带左右边框）
function Write-BorderedLine {
    param(
        [string]$Text,
        [int]$Width,
        [switch]$IsHeader,
        [switch]$IsFooter
    )

    $b = $script:Border
    $a = $script:ANSI

    if ($IsHeader) {
        # 顶部边框
        Write-Host "$($a.Cyan)$($b.TL)$($b.H * $Width)$($b.TR)$($a.Reset)"
    } elseif ($IsFooter) {
        # 底部边框
        Write-Host "$($a.Cyan)$($b.BL)$($b.H * $Width)$($b.BR)$($a.Reset)"
    } else {
        # 普通行
        $content = $Text.PadRight($Width).Substring(0, [Math]::Min($Text.Length, $Width))
        Write-Host "$($a.Cyan)$($b.V)$($a.Reset)$content$($a.Cyan)$($b.V)$($a.Reset)"
    }
}

# 绘制分隔线
function Write-Separator {
    param([int]$Width)
    $b = $script:Border
    $a = $script:ANSI
    Write-Host "$($a.Cyan)$($b.LT)$($b.H * $Width)$($b.RT)$($a.Reset)"
}
```

**Step 3: 测试绘图函数**

在 `tui.ps1` 末尾临时添加测试代码：

```powershell
# 测试代码（稍后删除）
if ($MyInvocation.InvocationName -ne '.') {
    Clear-Screen
    Write-BorderedLine "" 60 -IsHeader
    Write-BorderedLine "  测试标题" 60
    Write-Separator 60
    Write-BorderedLine "  内容行 1" 60
    Write-BorderedLine "  内容行 2" 60
    Write-BorderedLine "" 60 -IsFooter
    Show-Cursor
}
```

运行: `pwsh -File tui.ps1`
预期: 显示一个带边框的测试框

**Step 4: 删除测试代码并 Commit**

```bash
git add tui.ps1
git commit -m "feat: 添加 TUI 绘图辅助函数"
```

---

## Task 3: 实现 Show-ProfileSelector 选择器

**Files:**
- Modify: `tui.ps1`

**Step 1: 实现 Show-ProfileSelector 函数**

```powershell
<#
.SYNOPSIS
显示配置选择列表

.PARAMETER Profiles
配置列表，每项包含 alias, name, isCurrent

.PARAMETER Title
对话框标题

.OUTPUTS
选中的配置别名，或 $null（用户取消）
#>
function Show-ProfileSelector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$Profiles,

        [Parameter(Mandatory=$false)]
        [string]$Title = "选择配置"
    )

    # 空列表处理
    if ($Profiles.Count -eq 0) {
        $width = 50
        Clear-Screen
        Hide-Cursor
        Write-BorderedLine "" $width -IsHeader
        Write-BorderedLine "" $width
        Write-BorderedLine "  暂无配置，使用 cc new 创建" $width
        Write-BorderedLine "" $width
        Write-BorderedLine "  按任意键退出" $width
        Write-BorderedLine "" $width -IsFooter
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Show-Cursor
        return $null
    }

    $width = 60
    $selectedIndex = 0
    $a = $script:ANSI

    # 计算列表区域起始行
    $headerLines = 4  # 标题 + 空行 + 上边框 + 列表头
    $footerLines = 3  # 空行 + 帮助 + 下边框

    # 隐藏光标
    Hide-Cursor

    # 主循环
    while ($true) {
        # 清屏并绘制界面
        Clear-Screen
        Write-BorderedLine "" $width -IsHeader
        Write-BorderedLine "  ✦ $Title" $width
        Write-BorderedLine "" $width
        Write-Separator $width

        # 绘制选项列表
        for ($i = 0; $i -lt $Profiles.Count; $i++) {
            $item = $Profiles[$i]
            $isSelected = ($i -eq $selectedIndex)

            # 构建显示文本
            $marker = if ($item.isCurrent) { "$($a.Green)●$($a.Reset)" } else { " " }
            $aliasText = $item.alias.PadRight(12)
            $nameText = $item.name

            $lineText = "    $marker $aliasText $nameText"

            # 高亮选中项
            if ($isSelected) {
                $lineText = "$($a.Reverse)$lineText$($a.Reset)"
            }

            Write-BorderedLine $lineText $width
        }

        Write-BorderedLine "" $width
        Write-BorderedLine "  ● 当前使用的配置" $width
        Write-BorderedLine "" $width

        # 帮助文字
        $helpText = "  ↑↓ 选择 │ Enter 确认 │ Esc 取消"
        Write-BorderedLine "$($a.BrightBlack)$helpText$($a.Reset)" $width
        Write-BorderedLine "" $width -IsFooter

        # 读取按键
        $key = Read-Key

        switch ($key.Key) {
            'UpArrow' {
                $selectedIndex = [Math]::Max(0, $selectedIndex - 1)
            }
            'DownArrow' {
                $selectedIndex = [Math]::Min($Profiles.Count - 1, $selectedIndex + 1)
            }
            'Enter' {
                Show-Cursor
                return $Profiles[$selectedIndex].alias
            }
            'Escape' {
                Show-Cursor
                return $null
            }
        }
    }
}
```

**Step 2: 测试选择器**

在 `tui.ps1` 末尾临时添加：

```powershell
# 测试代码
if ($MyInvocation.InvocationName -ne '.') {
    $testProfiles = @(
        @{ alias = "glm"; name = "智谱 GLM"; isCurrent = $true }
        @{ alias = "deepseek"; name = "DeepSeek AI"; isCurrent = $false }
        @{ alias = "openrouter"; name = "OpenRouter"; isCurrent = $false }
    )

    $result = Show-ProfileSelector -Profiles $testProfiles -Title "测试选择器"
    Clear-Screen
    Write-Host "选中: $result"
}
```

运行: `pwsh -File tui.ps1`
预期: 显示配置选择列表，可用上下键选择，Enter 确认，Esc 取消

**Step 3: 删除测试代码并 Commit**

```bash
git add tui.ps1
git commit -m "feat: 实现 Show-ProfileSelector 选择器"
```

---

## Task 4: 实现 Show-ConfigForm 表单（基础版）

**Files:**
- Modify: `tui.ps1`

**Step 1: 实现表单字段定义和验证**

```powershell
# 表单字段定义
$script:FormFields = @(
    @{ Key = 'alias'; Label = '别名'; Required = $true }
    @{ Key = 'name'; Label = '显示名称'; Required = $true }
    @{ Key = 'baseUrl'; Label = 'API 地址'; Required = $true }
    @{ Key = 'token'; Label = '认证令牌'; Required = $true; Masked = $true }
    @{ Key = 'model'; Label = '默认模型'; Required = $true }
    @{ Key = 'sonnetModel'; Label = 'Sonnet'; Required = $false }
    @{ Key = 'opusModel'; Label = 'Opus'; Required = $false }
    @{ Key = 'haikuModel'; Label = 'Haiku'; Required = $false }
    @{ Key = 'reasoningModel'; Label = '推理模型'; Required = $false }
)

# 字段验证函数
function Test-FormField {
    param(
        [string]$Key,
        [string]$Value,
        [string[]]$ExistingAliases,
        [switch]$IsEdit
    )

    switch ($Key) {
        'alias' {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                return "别名不能为空"
            }
            if ($Value -notmatch '^[a-z0-9-]+$') {
                return "别名只能包含小写字母、数字和连字符"
            }
            if (-not $IsEdit -and $Value -in $ExistingAliases) {
                return "别名已存在"
            }
        }
        'name' {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                return "显示名称不能为空"
            }
        }
        'baseUrl' {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                return "API 地址不能为空"
            }
            if ($Value -notmatch '^https?://') {
                return "API 地址必须以 http:// 或 https:// 开头"
            }
        }
        'token' {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                return "认证令牌不能为空"
            }
        }
        'model' {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                return "默认模型不能为空"
            }
        }
    }
    return $null
}
```

**Step 2: 实现 Show-ConfigForm 函数（简化版，不含完整字段编辑）**

```powershell
<#
.SYNOPSIS
显示配置表单

.PARAMETER ExistingConfig
现有配置（编辑模式）

.PARAMETER IsEdit
是否为编辑模式

.PARAMETER ExistingAliases
现有别名列表（用于唯一性验证）

.OUTPUTS
配置对象 @{alias; name; env: @{...}}，或 $null（用户取消）
#>
function Show-ConfigForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$ExistingConfig,

        [Parameter(Mandatory=$false)]
        [switch]$IsEdit,

        [Parameter(Mandatory=$false)]
        [string[]]$ExistingAliases
    )

    $width = 60
    $a = $script:ANSI

    # 初始化字段值
    $values = @{}
    $errors = @{}

    foreach ($field in $script:FormFields) {
        $key = $field.Key
        if ($ExistingConfig) {
            switch ($key) {
                'alias' { $values[$key] = $ExistingConfig.alias }
                'name' { $values[$key] = $ExistingConfig.name }
                'baseUrl' { $values[$key] = $ExistingConfig.env.ANTHROPIC_BASE_URL }
                'token' { $values[$key] = $ExistingConfig.env.ANTHROPIC_AUTH_TOKEN }
                'model' { $values[$key] = $ExistingConfig.env.ANTHROPIC_MODEL }
                'sonnetModel' { $values[$key] = $ExistingConfig.env.ANTHROPIC_DEFAULT_SONNET_MODEL }
                'opusModel' { $values[$key] = $ExistingConfig.env.ANTHROPIC_DEFAULT_OPUS_MODEL }
                'haikuModel' { $values[$key] = $ExistingConfig.env.ANTHROPIC_DEFAULT_HAIKU_MODEL }
                'reasoningModel' { $values[$key] = $ExistingConfig.env.ANTHROPIC_REASONING_MODEL }
            }
        } else {
            $values[$key] = ''
        }
    }

    $fieldIndex = 0
    $tokenVisible = $false

    Hide-Cursor

    # 主循环
    while ($true) {
        Clear-Screen

        $title = if ($IsEdit) { "编辑配置" } else { "新建配置" }
        Write-BorderedLine "" $width -IsHeader
        Write-BorderedLine "  ✦ $title" $width
        Write-BorderedLine "" $width

        # 绘制字段
        for ($i = 0; $i -lt $script:FormFields.Count; $i++) {
            $field = $script:FormFields[$i]
            $isCurrentField = ($i -eq $fieldIndex)
            $value = $values[$field.Key]
            $error = $errors[$field.Key]

            # 模型配置分隔符
            if ($field.Key -eq 'model') {
                Write-BorderedLine "  ── 模型配置 (留空使用默认值) ──" $width
            }

            # 显示值（令牌可隐藏）
            $displayValue = if ($field.Masked -and -not $tokenVisible -and $value) {
                '*' * [Math]::Min($value.Length, 20)
            } else {
                $value
            }

            # 必填标记
            $requiredMark = if ($field.Required) { " *必填" } else { "" }

            # 构建行文本
            $label = $field.Label.PadRight(8)
            $inputBox = "[$($displayValue.PadRight(22).Substring(0, [Math]::Min($displayValue.Length, 22)))]"

            # 令牌显隐按钮
            $maskToggle = if ($field.Masked) {
                $maskState = if ($tokenVisible) { "● 显示" } else { "○ 隐藏" }
                "  $maskState"
            } else { "" }

            $lineText = "  $label $inputBox$requiredMark$maskToggle"

            # 高亮当前字段
            if ($isCurrentField) {
                $lineText = "$($a.Reverse)$lineText$($a.Reset)"
            }

            Write-BorderedLine $lineText $width

            # 显示错误
            if ($error) {
                Write-BorderedLine "             └─ $($a.BrightRed)✗ $error$($a.Reset)" $width
            }
        }

        Write-BorderedLine "" $width

        # 帮助文字
        $helpText = "  ↑↓切换 │ Tab下一项 │ Space显隐令牌 │ Ctrl+S保存 │ Esc取消"
        Write-BorderedLine "$($a.BrightBlack)$helpText$($a.Reset)" $width
        Write-BorderedLine "" $width -IsFooter

        # 读取按键
        $key = Read-Key
        $currentField = $script:FormFields[$fieldIndex]

        switch ($key.Key) {
            'UpArrow' {
                $fieldIndex = [Math]::Max(0, $fieldIndex - 1)
            }
            'DownArrow' {
                $fieldIndex = [Math]::Min($script:FormFields.Count - 1, $fieldIndex + 1)
            }
            'Tab' {
                $fieldIndex = ($fieldIndex + 1) % $script:FormFields.Count
            }
            'Enter' {
                # 如果是令牌字段，切换显隐
                if ($currentField.Masked) {
                    $tokenVisible = -not $tokenVisible
                }
            }
            'Spacebar' {
                if ($currentField.Masked) {
                    $tokenVisible = -not $tokenVisible
                }
            }
            'Escape' {
                Show-Cursor
                return $null
            }
            default {
                # Ctrl+S 保存
                if (Test-CtrlKey $key 's') {
                    # 验证所有必填字段
                    $hasErrors = $false
                    $errors = @{}

                    foreach ($field in $script:FormFields) {
                        if ($field.Required -or $values[$field.Key]) {
                            $error = Test-FormField -Key $field.Key -Value $values[$field.Key] `
                                -ExistingAliases $ExistingAliases -IsEdit:$IsEdit
                            if ($error) {
                                $errors[$field.Key] = $error
                                $hasErrors = $true
                            }
                        }
                    }

                    if (-not $hasErrors) {
                        Show-Cursor

                        # 构建返回对象
                        $model = $values['model']
                        return @{
                            alias = $values['alias']
                            name = $values['name']
                            env = @{
                                ANTHROPIC_AUTH_TOKEN = $values['token']
                                ANTHROPIC_BASE_URL = $values['baseUrl']
                                ANTHROPIC_MODEL = $model
                                ANTHROPIC_DEFAULT_SONNET_MODEL = if ($values['sonnetModel']) { $values['sonnetModel'] } else { $model }
                                ANTHROPIC_DEFAULT_OPUS_MODEL = if ($values['opusModel']) { $values['opusModel'] } else { $model }
                                ANTHROPIC_DEFAULT_HAIKU_MODEL = if ($values['haikuModel']) { $values['haikuModel'] } else { $model }
                                ANTHROPIC_REASONING_MODEL = if ($values['reasoningModel']) { $values['reasoningModel'] } else { $model }
                            }
                            skipDangerousModePermissionPrompt = $true
                        }
                    }
                }
            }
        }
    }
}
```

**Step 3: Commit 基础表单**

```bash
git add tui.ps1
git commit -m "feat: 实现 Show-ConfigForm 表单（基础版）"
```

---

## Task 5: 实现表单输入功能

**Files:**
- Modify: `tui.ps1`

**Step 1: 添加输入模式处理**

在 `Show-ConfigForm` 的主循环中，需要支持字符输入。修改 `switch` 语句的 `default` 分支：

```powershell
            default {
                # Ctrl+S 保存
                if (Test-CtrlKey $key 's') {
                    # ... 保存逻辑（保持不变）
                }
                # 字符输入
                elseif ($key.Character -and [char]::IsControl($key.Character) -eq $false) {
                    # 编辑模式且当前是别名字段，不允许修改
                    if ($IsEdit -and $currentField.Key -eq 'alias') {
                        continue
                    }

                    $values[$currentField.Key] += $key.Character
                    # 清除该字段错误
                    $errors[$currentField.Key] = $null
                }
                # Backspace 删除
                elseif ($key.Key -eq 'Backspace') {
                    if ($IsEdit -and $currentField.Key -eq 'alias') {
                        continue
                    }
                    $current = $values[$currentField.Key]
                    if ($current.Length -gt 0) {
                        $values[$currentField.Key] = $current.Substring(0, $current.Length - 1)
                    }
                    $errors[$currentField.Key] = $null
                }
            }
```

**Step 2: 测试表单输入**

在 `tui.ps1` 末尾临时添加：

```powershell
# 测试代码
if ($MyInvocation.InvocationName -ne '.') {
    $result = Show-ConfigForm -Title "测试表单"
    Clear-Screen
    if ($result) {
        Write-Host "保存的配置:"
        $result | ConvertTo-Json -Depth 3
    } else {
        Write-Host "用户取消"
    }
}
```

运行: `pwsh -File tui.ps1`
预期: 可以输入各字段，Ctrl+S 保存，Esc 取消

**Step 3: 删除测试代码并 Commit**

```bash
git add tui.ps1
git commit -m "feat: 实现表单字符输入功能"
```

---

## Task 6: 创建主脚本 cc.ps1 骨架

**Files:**
- Create: `cc.ps1`

**Step 1: 创建 cc.ps1 基础结构**

```powershell
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

# 主入口
Ensure-ConfigDir

$command = $args[0]
$param = $args[1]

switch ($command) {
    $null { Show-Help }
    'use' { Write-Host "use 命令 - 待实现" }
    'list' { Write-Host "list 命令 - 待实现" }
    'new' { Write-Host "new 命令 - 待实现" }
    'edit' { Write-Host "edit 命令 - 待实现" }
    'rm' { Write-Host "rm 命令 - 待实现" }
    'test' { Write-Host "test 命令 - 待实现" }
    default { Write-Host "未知命令: $command" -ForegroundColor Red; Show-Help }
}
```

**Step 2: 测试基础脚本**

运行: `pwsh -File cc.ps1`
预期: 显示帮助信息和当前配置（无）

**Step 3: Commit**

```bash
git add cc.ps1
git commit -m "feat: 创建 cc.ps1 主脚本骨架"
```

---

## Task 7: 实现 list 命令

**Files:**
- Modify: `cc.ps1`

**Step 1: 实现 Show-List 函数**

在 `cc.ps1` 的 `switch` 语句之前添加：

```powershell
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
```

**Step 2: 更新 switch 分支**

```powershell
    'list' { Show-List }
```

**Step 3: 测试**

运行: `pwsh -File cc.ps1 list`
预期: 显示 "暂无配置" 提示

**Step 4: Commit**

```bash
git add cc.ps1
git commit -m "feat: 实现 list 命令"
```

---

## Task 8: 实现 new 命令

**Files:**
- Modify: `cc.ps1`

**Step 1: 实现 New-Profile 函数**

```powershell
# 创建新配置
function New-Profile {
    $currentAlias = Get-CurrentAlias
    $profiles = Get-Profiles -CurrentAlias $currentAlias
    $existingAliases = $profiles | ForEach-Object { $_.alias }

    $result = Show-ConfigForm -ExistingAliases $existingAliases -Title "新建配置"

    if ($result) {
        # 保存配置文件
        $profilePath = "$script:PROFILES_DIR/$($result.alias).json"
        $result | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$($result.alias)' 创建成功" -ForegroundColor Green
        Write-Host ""
    }
}
```

**Step 2: 更新 switch 分支**

```powershell
    'new' { New-Profile }
```

**Step 3: 测试完整流程**

运行: `pwsh -File cc.ps1 new`
预期: 显示表单，填写后 Ctrl+S 保存

运行: `pwsh -File cc.ps1 list`
预期: 显示新创建的配置

**Step 4: Commit**

```bash
git add cc.ps1
git commit -m "feat: 实现 new 命令"
```

---

## Task 9: 实现 use 命令

**Files:**
- Modify: `cc.ps1`

**Step 1: 实现 Use-Profile 函数**

```powershell
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
```

**Step 2: 更新 switch 分支**

```powershell
    'use' { Use-Profile -Alias $param }
```

**Step 3: 测试**

运行: `pwsh -File cc.ps1 use`
预期: 显示选择器，选择后启动 Claude Code

**Step 4: Commit**

```bash
git add cc.ps1
git commit -m "feat: 实现 use 命令"
```

---

## Task 10: 实现 edit 命令

**Files:**
- Modify: `cc.ps1`

**Step 1: 实现 Edit-Profile 函数**

```powershell
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
    $result = Show-ConfigForm -ExistingConfig $existingHashtable -IsEdit -ExistingAliases $existingAliases -Title "编辑配置"

    if ($result) {
        # 保存配置（使用原别名）
        $result.alias = $Alias
        $result | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$Alias' 已更新" -ForegroundColor Green
        Write-Host ""
    }
}
```

**Step 2: 更新 switch 分支**

```powershell
    'edit' { Edit-Profile -Alias $param }
```

**Step 3: Commit**

```bash
git add cc.ps1
git commit -m "feat: 实现 edit 命令"
```

---

## Task 11: 实现 rm 命令

**Files:**
- Modify: `cc.ps1`

**Step 1: 实现 Remove-Profile 函数**

```powershell
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
```

**Step 2: 更新 switch 分支**

```powershell
    'rm' { Remove-Profile -Alias $param }
```

**Step 3: Commit**

```bash
git add cc.ps1
git commit -m "feat: 实现 rm 命令"
```

---

## Task 12: 实现 test 命令

**Files:**
- Modify: `cc.ps1`

**Step 1: 实现 Test-ApiConnection 函数**

```powershell
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
        $errorMsg = switch ($statusCode) {
            401 { "认证失败，请检查令牌" }
            403 { "访问被拒绝" }
            404 { "API 端点不存在" }
            500 { "服务器内部错误" }
            default { "连接失败: $($_.Exception.Message)" }
        }

        return @{
            Success = $false
            Message = $errorMsg
        }
    }
}
```

**Step 2: 实现 Test-Profile 函数**

```powershell
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
    }

    Write-Host ""
}
```

**Step 3: 更新 switch 分支**

```powershell
    'test' { Test-Profile -Alias $param }
```

**Step 4: Commit**

```bash
git add cc.ps1
git commit -m "feat: 实现 test 命令"
```

---

## Task 13: 最终测试与清理

**Files:**
- Modify: `cc.ps1`
- Modify: `tui.ps1`

**Step 1: 确保所有测试代码已删除**

检查 `tui.ps1` 末尾是否有测试代码，如有则删除。

**Step 2: 端到端测试**

```powershell
# 测试所有命令
pwsh -File cc.ps1           # 帮助
pwsh -File cc.ps1 list      # 列表（空）
pwsh -File cc.ps1 new       # 创建配置
pwsh -File cc.ps1 list      # 列表（有配置）
pwsh -File cc.ps1 test glm  # 测试连接
pwsh -File cc.ps1 edit glm  # 编辑配置
pwsh -File cc.ps1 use glm   # 启动 Claude Code
pwsh -File cc.ps1 rm glm    # 删除配置
```

**Step 3: 最终 Commit**

```bash
git add -A
git commit -m "chore: 清理测试代码，完成实现"
```

---

## 文件清单

完成后项目结构：

```
cc-helper/
├── cc.ps1              # 主脚本（~250行）
├── tui.ps1             # TUI 模块（~400行）
└── docs/
    └── plans/
        ├── 2026-03-04-cc-config-manager-design.md  # 设计文档
        └── 2026-03-04-cc-config-manager-impl.md    # 本实现计划
```

配置目录：

```
~/.cc/
├── profiles/           # 配置文件目录
│   ├── glm.json
│   └── ...
└── current             # 当前配置别名
```
