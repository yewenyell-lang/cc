# 键盘输入诊断脚本 - 完整测试
Write-Host "键盘完整测试" -ForegroundColor Cyan
Write-Host "测试: 1)单独按 S  2)按 Ctrl+S  3)按 Q 退出" -ForegroundColor Yellow
Write-Host ""

# ControlKeyState 标志
$RightCtrlPressed = 4
$LeftCtrlPressed = 8

while ($true) {
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

    # 检测 Ctrl 键（使用整数值）
    $ctrlPressed = ($key.ControlKeyState -band $RightCtrlPressed) -or
                   ($key.ControlKeyState -band $LeftCtrlPressed)

    # 尝试转换为 ConsoleKey
    $consoleKey = $null
    try {
        $consoleKey = [ConsoleKey]$key.VirtualKeyCode
    } catch {
        $consoleKey = "(无效: $($key.VirtualKeyCode))"
    }

    Write-Host "VK=$($key.VirtualKeyCode) Char='$($key.Character)'($([int]$key.Character)) Ctrl=$ctrlPressed Key=$consoleKey"

    # 检测 Ctrl+S
    if ($ctrlPressed -and $consoleKey -eq [ConsoleKey]::S) {
        Write-Host ">>> 检测到 Ctrl+S!" -ForegroundColor Green
    }

    # 检测 Q 退出
    if ($key.Character -eq 'Q' -or $key.Character -eq 'q') {
        return
    }
}
