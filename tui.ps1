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
