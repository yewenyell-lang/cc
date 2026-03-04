# 键盘输入诊断脚本
# 用于测试 $Host.UI.RawUI.ReadKey() 的返回值

Write-Host "键盘输入诊断工具" -ForegroundColor Cyan
Write-Host "按任意键测试，按 Q 退出" -ForegroundColor Yellow
Write-Host ""

while ($true) {
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

    Write-Host "=== 按键信息 ===" -ForegroundColor Green
    Write-Host "对象类型: $($key.GetType().FullName)"
    Write-Host ""
    Write-Host "所有属性:"
    $key.PSObject.Properties | ForEach-Object {
        Write-Host "  $($_.Name) = $($_.Value)"
    }
    Write-Host ""

    # 检查是否有 VirtualKeyCode
    if ($key.VirtualKeyCode) {
        Write-Host "VirtualKeyCode: $($key.VirtualKeyCode)"
        $consoleKey = [ConsoleKey]$key.VirtualKeyCode
        Write-Host "转换为 ConsoleKey: $consoleKey"
    }

    Write-Host ""
    Write-Host "--- 按任意键继续，Q 退出 ---" -ForegroundColor DarkGray

    # 检测退出
    if ($key.Character -eq 'Q' -or $key.Character -eq 'q') {
        return
    }
}
