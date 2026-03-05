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

# 边框字符 - 左侧竖线样式
$script:Border = @{
    Bar = '▌'  # 左侧粗竖线
}

# 读取单个按键
function Read-Key {
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    # KeyInfo 结构使用 VirtualKeyCode，需要转换为 ConsoleKey 枚举
    $consoleKey = [ConsoleKey]$key.VirtualKeyCode
    return @{
        Key       = $consoleKey      # [ConsoleKey] 枚举
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

# 绘制文本行（左侧竖线样式）
function Write-LeftBarLine {
    param(
        [string]$Text,
        [switch]$NoBar
    )

    $b = $script:Border
    $a = $script:ANSI

    if ($NoBar) {
        Write-Host "  $Text"
    } else {
        Write-Host "$($a.Cyan)$($b.Bar)$($a.Reset) $Text"
    }
}

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
        Clear-Screen
        Hide-Cursor
        Write-Host ""
        Write-LeftBarLine "暂无配置，使用 cc new 创建"
        Write-Host ""
        Write-LeftBarLine "按任意键退出"
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Show-Cursor
        return $null
    }

    $selectedIndex = 0
    $a = $script:ANSI
    $b = $script:Border

    # 隐藏光标
    Hide-Cursor

    # 主循环
    while ($true) {
        # 清屏并绘制界面
        Clear-Screen
        Write-Host ""
        Write-LeftBarLine "$($a.Cyan)$Title$($a.Reset)"
        Write-LeftBarLine ""

        # 绘制选项列表
        for ($i = 0; $i -lt $Profiles.Count; $i++) {
            $item = $Profiles[$i]
            $isSelected = ($i -eq $selectedIndex)

            # 构建显示文本
            $aliasText = $item.alias.PadRight(12)
            $nameText = $item.name
            $currentMark = if ($item.isCurrent) { " $($a.Green)(当前)$($a.Reset)" } else { "" }

            # 选中项：箭头 + 颜色高亮
            if ($isSelected) {
                Write-LeftBarLine "$($a.Cyan)▶$($a.Reset) $aliasText $nameText$currentMark"
            } else {
                Write-LeftBarLine "  $aliasText $nameText$currentMark"
            }
        }

        Write-LeftBarLine ""
        Write-LeftBarLine "$($a.BrightBlack)↑↓ 选择  Enter 确认  Esc 取消$($a.Reset)"

        # 读取按键
        $key = Read-Key

        switch ($key.Key) {
            ([ConsoleKey]::UpArrow) {
                $selectedIndex = [Math]::Max(0, $selectedIndex - 1)
            }
            ([ConsoleKey]::DownArrow) {
                $selectedIndex = [Math]::Min($Profiles.Count - 1, $selectedIndex + 1)
            }
            ([ConsoleKey]::Enter) {
                Show-Cursor
                return $Profiles[$selectedIndex].alias
            }
            ([ConsoleKey]::Escape) {
                Show-Cursor
                return $null
            }
        }
    }
}

<#
.SYNOPSIS
显示多选列表

.PARAMETER Items
选项列表，每项包含 alias, name, isCurrent, isSelected

.PARAMETER Title
对话框标题

.OUTPUTS
选中的项数组，或 $null（用户取消）
#>
function Show-MultiSelectSelector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$Items,

        [Parameter(Mandatory=$false)]
        [string]$Title = "选择项目"
    )

    # 空列表处理
    if ($Items.Count -eq 0) {
        Clear-Screen
        Hide-Cursor
        Write-Host ""
        Write-LeftBarLine "暂无可选项目"
        Write-Host ""
        Write-LeftBarLine "按任意键退出"
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Show-Cursor
        return $null
    }

    # 初始化选中状态
    foreach ($item in $Items) {
        if (-not $item.ContainsKey('isSelected')) {
            $item.isSelected = $false
        }
    }

    $selectedIndex = 0
    $a = $script:ANSI

    Hide-Cursor

    # 主循环
    while ($true) {
        Clear-Screen
        Write-Host ""
        Write-LeftBarLine "$($a.Cyan)$Title$($a.Reset)"
        Write-LeftBarLine ""

        # 绘制选项列表
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            $isFocused = ($i -eq $selectedIndex)
            $checkMark = if ($item.isSelected) { "$($a.Green)●$($a.Reset)" } else { "○" }
            $currentMark = if ($item.isCurrent) { " $($a.Green)(当前)$($a.Reset)" } else { "" }

            $aliasText = $item.alias.PadRight(12)
            $nameText = $item.name

            if ($isFocused) {
                Write-LeftBarLine "$($a.Cyan)▶$($a.Reset) $checkMark $aliasText $nameText$currentMark"
            } else {
                Write-LeftBarLine "  $checkMark $aliasText $nameText$currentMark"
            }
        }

        Write-LeftBarLine ""
        Write-LeftBarLine "$($a.BrightBlack)↑↓ 移动  Space 选择  Enter 确认  Esc 取消$($a.Reset)"

        $key = Read-Key

        switch ($key.Key) {
            ([ConsoleKey]::UpArrow) {
                $selectedIndex = [Math]::Max(0, $selectedIndex - 1)
            }
            ([ConsoleKey]::DownArrow) {
                $selectedIndex = [Math]::Min($Items.Count - 1, $selectedIndex + 1)
            }
            ([ConsoleKey]::Spacebar) {
                $Items[$selectedIndex].isSelected = -not $Items[$selectedIndex].isSelected
            }
            ([ConsoleKey]::Enter) {
                Show-Cursor
                $selected = $Items | Where-Object { $_.isSelected }
                if ($selected.Count -eq 0) {
                    return @()
                }
                return @($selected)
            }
            ([ConsoleKey]::Escape) {
                Show-Cursor
                return $null
            }
        }
    }
}

# 表单字段定义
$script:FormFields = @(
    @{ Key = 'alias'; Label = '别名'; Required = $true }
    @{ Key = 'name'; Label = '显示名称'; Required = $true }
    @{ Key = 'baseUrl'; Label = 'API 地址'; Required = $true }
    @{ Key = 'token'; Label = '认证令牌'; Required = $true; Masked = $true }
    @{ Key = 'model'; Label = '默认模型'; Required = $true }
    @{ Key = 'models'; Label = '可选模型'; Required = $false; IsArray = $true }
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
                'models' {
                    $models = @()
                    if ($ExistingConfig.env.PSObject.Properties.Name -contains 'ANTHROPIC_MODELS') {
                        $modelsJson = $ExistingConfig.env.ANTHROPIC_MODELS
                        if ($modelsJson) {
                            $models = $modelsJson | ConvertFrom-Json
                            if ($models -is [String]) {
                                $models = @($models)
                            }
                        }
                    }
                    $values[$key] = $models
                }
            }
        } else {
            $values[$key] = if ($field.IsArray) { @() } else { '' }
        }
    }

    $fieldIndex = 0
    $tokenVisible = $false

    Hide-Cursor

    # 主循环
    while ($true) {
        Clear-Screen

        $b = $script:Border
        $title = if ($IsEdit) { "编辑配置" } else { "新建配置" }
        Write-Host ""
        Write-LeftBarLine "$($a.Cyan)$title$($a.Reset)"
        Write-LeftBarLine ""

        # 绘制字段
        for ($i = 0; $i -lt $script:FormFields.Count; $i++) {
            $field = $script:FormFields[$i]
            $isCurrentField = ($i -eq $fieldIndex)
            $value = $values[$field.Key]
            $error = $errors[$field.Key]

            # 模型配置分隔符
            if ($field.Key -eq 'model') {
                Write-LeftBarLine "$($a.Dim)── 模型配置 (留空使用默认值) ──$($a.Reset)"
            }

            # 显示值（令牌可隐藏）
            $displayValue = if ($field.Masked -and -not $tokenVisible -and $value) {
                '*' * [Math]::Min($value.Length, 20)
            } elseif ($field.IsArray) {
                $arr = if ($value) { $value } else { @() }
                "$($arr.Count) 个模型)"
            } else {
                $value
            }

            # 必填标记
            $requiredMark = if ($field.Required) { " *" } else { "" }

            # 构建行文本
            $label = $field.Label
            $inputBox = "[$($displayValue.PadRight(22).Substring(0, [Math]::Min($displayValue.Length, 22)))]"

            # 令牌显隐按钮
            $maskToggle = if ($field.Masked) {
                $maskState = if ($tokenVisible) { "●" } else { "○" }
                "  $maskState"
            } else { "" }

            # 选中项使用箭头 + 颜色高亮
            if ($isCurrentField) {
                Write-LeftBarLine "$($a.Cyan)▶$($a.Reset) $label $inputBox$requiredMark$maskToggle"
            } else {
                Write-LeftBarLine "  $label $inputBox$requiredMark$maskToggle"
            }

            # 显示错误
            if ($error) {
                Write-Host "        $($a.BrightRed)└─ ✗ $error$($a.Reset)"
            }
        }

        Write-LeftBarLine ""

        # 帮助文字
        Write-LeftBarLine "$($a.BrightBlack)↑↓ 切换 │ Tab 下一项 │ Space 显隐令牌 │ F5 保存 │ Esc 取消$($a.Reset)"

        # 读取按键
        $key = Read-Key
        $currentField = $script:FormFields[$fieldIndex]

        switch ($key.Key) {
            ([ConsoleKey]::UpArrow) {
                $fieldIndex = [Math]::Max(0, $fieldIndex - 1)
            }
            ([ConsoleKey]::DownArrow) {
                $fieldIndex = [Math]::Min($script:FormFields.Count - 1, $fieldIndex + 1)
            }
            ([ConsoleKey]::Tab) {
                $fieldIndex = ($fieldIndex + 1) % $script:FormFields.Count
            }
            ([ConsoleKey]::Enter) {
                # 如果是令牌字段，切换显隐
                if ($currentField.Masked) {
                    $tokenVisible = -not $tokenVisible
                }
                # 如果是数组字段，弹出模型输入表单
                if ($currentField.IsArray) {
                    $models = Show-ModelInputForm -ExistingModels $values['models']
                    $values['models'] = $models
                }
            }
            ([ConsoleKey]::Spacebar) {
                if ($currentField.Masked) {
                    $tokenVisible = -not $tokenVisible
                }
            }
            ([ConsoleKey]::Backspace) {
                # 编辑模式且当前是别名字段，不允许修改
                if ($IsEdit -and $currentField.Key -eq 'alias') {
                    continue
                }
                $current = $values[$currentField.Key]
                if ($current.Length -gt 0) {
                    $values[$currentField.Key] = $current.Substring(0, $current.Length - 1)
                }
                $errors[$currentField.Key] = $null
            }
            ([ConsoleKey]::F5) {
                # F5 保存
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
                    $models = $values['models']
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
                            ANTHROPIC_MODELS = if ($models -and $models.Count -gt 0) { ($models | ConvertTo-Json) } else { $null }
                        }
                        skipDangerousModePermissionPrompt = $true
                    }
                }
            }
            ([ConsoleKey]::Escape) {
                Show-Cursor
                return $null
            }
            default {
                # 字符输入
                if ($key.Character -and [char]::IsControl($key.Character) -eq $false) {
                    # 编辑模式且当前是别名字段，不允许修改
                    if ($IsEdit -and $currentField.Key -eq 'alias') {
                        continue
                    }

                    $values[$currentField.Key] += $key.Character
                    # 清除该字段错误
                    $errors[$currentField.Key] = $null
                }
            }
        }
    }
}


# 显示模型输入表单
function Show-ModelInputForm {
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$ExistingModels = @()
    )

    $a = $script:ANSI
    $models = @() + $ExistingModels

    while ($true) {
        Clear-Screen
        Write-Host ""
        Write-LeftBarLine "$($a.Cyan)添加可选模型$($a.Reset)"
        Write-LeftBarLine ""

        if ($models.Count -gt 0) {
            Write-LeftBarLine "已添加的模型："
            for ($i = 0; $i -lt $models.Count; $i++) {
                Write-LeftBarLine "  $($i + 1). $($models[$i])"
            }
            Write-LeftBarLine ""
        }

        Write-LeftBarLine "输入模型 ID（回车添加，空行结束）："
        Write-LeftBarLine ""

        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input)) {
            break
        }
        $models += $input.Trim()
    }

    return $models
}

# 显示模型选择器
function Show-ModelSelector {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Models,

        [Parameter(Mandatory=$false)]
        [string]$Title = "选择模型"
    )

    $a = $script:ANSI
    $selectedIndex = 0

    Hide-Cursor

    while ($true) {
        Clear-Screen
        Write-Host ""
        Write-Host " ┌─ $Title ─┐" -NoNewline
        Write-Host ""
        Write-Host ""

        for ($i = 0; $i -lt $Models.Count; $i++) {
            $model = $Models[$i]
            if ($i -eq $selectedIndex) {
                Write-Host " │ $($a.Cyan)▶ $($model)$($a.Reset)" -NoNewline
                Write-Host " │"
            } else {
                Write-Host " │   $model │"
            }
        }

        Write-Host " └────────────┘"
        Write-Host ""
        Write-Host "$($a.BrightBlack)↑↓ 选择 │ Enter 确认 │ Esc 取消$($a.Reset)"

        $key = Read-Key

        switch ($key) {
            'ArrowUp' {
                $selectedIndex = [Math]::Max(0, $selectedIndex - 1)
            }
            'ArrowDown' {
                $selectedIndex = [Math]::Min($Models.Count - 1, $selectedIndex + 1)
            }
            'Enter' {
                Show-Cursor
                return $Models[$selectedIndex]
            }
            'Escape' {
                Show-Cursor
                return $null
            }
        }
    }
}
