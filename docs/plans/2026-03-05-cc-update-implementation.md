# cc update 命令实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 cc.ps1 中添加 `update` 命令，实现从 GitHub 下载最新版本并更新本地文件的功能。

**Architecture:** 直接从 raw.githubusercontent.com 下载核心脚本文件，下载前备份本地文件，失败时恢复备份。

**Tech Stack:** PowerShell 7.0+

---

### Task 1: 添加 Update-CcHelper 函数

**Files:**
- Modify: `cc.ps1:1-20` (查看当前文件末尾位置)

**Step 1: 确定插入位置**

查看 cc.ps1 文件结构，找到 Uninstall-CcHelper 函数之后、主入口之前的位置。

Run: `grep -n "function\|# 主入口" cc.ps1`
Expected: 找到函数定义和主入口的行号

**Step 2: 添加 Update-CcHelper 函数**

在 Uninstall-CcHelper 函数之后（约第 510 行），添加:

```powershell
# 更新 cc-helper
function Update-CcHelper {
    $INSTALL_DIR = "$env:USERPROFILE\.cc"
    $BASE_URL = "https://raw.githubusercontent.com/yewenyell-lang/cc/main"
    $FILES = @("cc.ps1", "tui.ps1", "ccswitch.ps1")

    # 检查安装目录
    if (-not (Test-Path $INSTALL_DIR)) {
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 未安装 cc-helper，请先运行 install.ps1" -ForegroundColor Red
        return
    }

    Write-Host "正在更新 cc-helper..." -ForegroundColor Cyan

    $backupFiles = @()
    $tempFiles = @()

    try {
        # 备份并下载文件
        foreach ($file in $FILES) {
            $srcPath = "$INSTALL_DIR\$file"
            $bakPath = "$srcPath.bak"
            $tmpPath = "$env:TEMP\$file"

            # 备份原文件
            if (Test-Path $srcPath) {
                Copy-Item -Path $srcPath -Destination $bakPath -Force
                $backupFiles += $bakPath
            }

            # 下载新文件
            $url = "$BASE_URL/$file"
            Write-Host "下载: $url"
            try {
                Invoke-WebRequest -Uri $url -OutFile $tmpPath -ErrorAction Stop
                $tempFiles += $tmpPath
            }
            catch {
                throw "下载失败: $file - $_"
            }
        }

        # 替换文件
        foreach ($file in $FILES) {
            $srcPath = "$INSTALL_DIR\$file"
            $tmpPath = "$env:TEMP\$file"
            Move-Item -Path $tmpPath -Destination $srcPath -Force
            Write-Host "  更新: $file" -ForegroundColor Green
        }

        # 清理备份
        foreach ($bak in $backupFiles) {
            Remove-Item -Path $bak -Force -ErrorAction SilentlyContinue
        }

        Write-Host ""
        Write-Host "$($ANSI.BrightGreen)✓$($ANSI.Reset) 更新完成!" -ForegroundColor Green
    }
    catch {
        # 恢复备份
        foreach ($bak in $backupFiles) {
            $originalPath = $bak -replace '\.bak$', ''
            if (Test-Path $bak) {
                Move-Item -Path $bak -Destination $originalPath -Force
            }
        }

        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 更新失败: $_" -ForegroundColor Red
        Write-Host "请手动运行 install.ps1 进行更新" -ForegroundColor Yellow
    }
    finally {
        # 清理临时文件
        foreach ($tmp in $tempFiles) {
            if (Test-Path $tmp) {
                Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
```

**Step 3: 验证语法正确**

Run: `pwsh -NoProfile -Command "Get-Command ./cc.ps1 -Syntax" 2>&1 || echo "检查完成"`
Expected: 无语法错误

**Step 4: 提交**

```bash
git add cc.ps1
git commit -m "feat: 添加 cc update 命令"
```

---

### Task 2: 添加 switch 分支和帮助信息

**Files:**
- Modify: `cc.ps1:93` (帮助信息)
- Modify: `cc.ps1:523` (switch 分支)

**Step 1: 在帮助信息中添加 update 命令**

在 Show-Help 函数中，约第 93 行 `cc uninstall` 之后添加:

```powershell
Write-Host "  cc update      更新 cc-helper 到最新版本"
```

Run: `sed -i "s/cc uninstall    卸载 cc-helper/cc uninstall    卸载 cc-helper\n    Write-Host \"  cc update      更新 cc-helper 到最新版本\"/" cc.ps1`
Expected: 替换成功

**Step 2: 在 switch 中添加 update 分支**

在 switch 语句中，约第 523 行 `'uninstall'` 之后添加:

```powershell
'update' { Update-CcHelper }
```

Run: `sed -i "s/'uninstall' { Uninstall-CcHelper/'uninstall' { Uninstall-CcHelper }\n    'update' { Update-CcHelper }/" cc.ps1`
Expected: 替换成功

**Step 3: 验证**

Run: `grep -n "update" cc.ps1 | head -10`
Expected: 找到帮助信息和 switch 分支

**Step 4: 提交**

```bash
git add cc.ps1
git commit -m "feat: 添加 update 命令到 switch 和帮助信息"
```

---

### Task 3: 测试 update 命令

**Step 1: 模拟测试**

由于无法真正从 GitHub 下载（可能没有网络），可以检查命令是否能正确识别:

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File ./cc.ps1 update 2>&1 | head -20`
Expected: 显示"正在更新 cc-helper..." 或 "未安装 cc-helper"

**Step 2: 提交**

```bash
git add .
git commit -m "test: 验证 update 命令可执行"
```
