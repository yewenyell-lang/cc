# cc-switch 迁移功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 添加 `cc ccswitch` 命令，从旧版 cc-switch 的 SQLite 数据库迁移配置。

**Architecture:** 在 tui.ps1 中新增多选选择器函数，在 cc.ps1 中添加 SQLite 读取和迁移逻辑，复用现有左侧竖线样式。

**Tech Stack:** PowerShell 7+, sqlite3 CLI, ANSI escape sequences

---

### Task 1: 添加多选选择器函数

**Files:**
- Modify: `tui.ps1` (在 Show-ProfileSelector 函数后添加)

**Step 1: 添加 Show-MultiSelectSelector 函数**

在 `tui.ps1` 第 211 行后添加：

```powershell
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
```

**Step 2: 手动测试**

运行以下命令启动 PowerShell 并加载脚本测试语法：
```powershell
pwsh -Command ". ./tui.ps1; Write-Host 'Syntax OK'"
```
Expected: 输出 "Syntax OK"

---

### Task 2: 添加别名生成和 SQLite 读取函数

**Files:**
- Modify: `cc.ps1` (在 Ensure-ConfigDir 函数后添加)

**Step 1: 添加别名生成函数**

在 `cc.ps1` 第 19 行后添加：

```powershell
# 从名称生成别名
function Get-AliasFromName {
    param([string]$Name)

    # 转小写，替换空格为连字符，移除非法字符
    $alias = $Name.ToLower()
    $alias = $alias -replace '\s+', '-'
    $alias = $alias -replace '[^a-z0-9-]', ''
    return $alias
}
```

**Step 2: 添加 SQLite 读取函数**

继续添加：

```powershell
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
```

**Step 3: 手动测试语法**

```powershell
pwsh -Command ". ./cc.ps1; Write-Host 'Syntax OK'"
```
Expected: 输出 "Syntax OK"

---

### Task 3: 添加迁移主函数

**Files:**
- Modify: `cc.ps1` (在 Get-CcSwitchConfigs 函数后添加)

**Step 1: 添加 Import-FromCcSwitch 函数**

```powershell
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
```

**Step 2: 手动测试语法**

```powershell
pwsh -Command ". ./cc.ps1; Write-Host 'Syntax OK'"
```
Expected: 输出 "Syntax OK"

---

### Task 4: 添加命令入口

**Files:**
- Modify: `cc.ps1` (switch 语句部分)

**Step 1: 在 switch 中添加 ccswitch 命令**

修改 `cc.ps1` 第 488-497 行的 switch 语句：

```powershell
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
```

**Step 2: 更新帮助信息**

修改 `Show-Help` 函数中的命令列表部分（约第 82-89 行）：

```powershell
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
```

---

### Task 5: 集成测试

**Step 1: 测试帮助信息**

```powershell
pwsh -File cc.ps1
```
Expected: 显示帮助信息，包含 `cc ccswitch` 命令

**Step 2: 测试迁移功能**

```powershell
pwsh -File cc.ps1 ccswitch
```
Expected:
- 如果数据库存在：显示多选界面
- 如果数据库不存在：显示 "未找到 cc-switch 数据库"

**Step 3: 验证导入的配置**

```powershell
pwsh -File cc.ps1 ls
```
Expected: 列表中包含新导入的配置

---

### Task 6: 提交

```bash
git add tui.ps1 cc.ps1 docs/plans/2026-03-04-ccswitch-migration-design.md docs/plans/2026-03-04-ccswitch-migration-impl.md
git commit -m "feat: 添加 cc ccswitch 命令从 cc-switch 迁移配置"
```
