# cc sync 命令实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 cc.ps1 中添加 sync 命令，使用原生 git 将 profiles 配置同步到私有仓库。

**Architecture:** 使用 git clone 到临时目录，比较本地和远程文件的时间戳，执行双向合并后 push。

**Tech Stack:** PowerShell 7+, Git (SSH 认证)

---

## Task 1: 添加配置文件路径常量

**Files:**
- Modify: `cc.ps1:8-11`

**Step 1: 添加 CONFIG_FILE 常量**

在 `$script:CURRENT_FILE` 定义后添加：

```powershell
$script:CONFIG_FILE = "$script:CC_DIR/config.json"
```

**Step 2: 验证修改**

运行: `pwsh -NoProfile -Command ". ./cc.ps1; Write-Host $script:CONFIG_FILE"`

**Step 3: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加配置文件路径常量"
```

---

## Task 2: 实现环境检查函数

**Files:**
- Modify: `cc.ps1` (在 `Ensure-ConfigDir` 函数后)

**Step 1: 添加 Test-SyncEnvironment 函数**

```powershell
# 检查同步环境
function Test-SyncEnvironment {
    # 检查 git 是否安装
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 未安装 git" -ForegroundColor Red
        Write-Host "  请先安装 git: https://git-scm.com/downloads" -ForegroundColor Yellow
        Write-Host ""
        return $false
    }

    return $true
}
```

**Step 2: 验证函数存在**

运行: `pwsh -NoProfile -Command ". ./cc.ps1; Test-SyncEnvironment"`

**Step 3: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加环境检查函数"
```

---

## Task 3: 实现配置读写函数

**Files:**
- Modify: `cc.ps1` (在 `Test-SyncEnvironment` 函数后)

**Step 1: 添加 Get-SyncConfig 函数**

```powershell
# 获取同步配置
function Get-SyncConfig {
    if (-not (Test-Path $script:CONFIG_FILE)) {
        return $null
    }

    try {
        $config = Get-Content $script:CONFIG_FILE | ConvertFrom-Json
        return $config.sync
    }
    catch {
        return $null
    }
}
```

**Step 2: 添加 Set-SyncConfig 函数**

```powershell
# 保存同步配置
function Set-SyncConfig {
    param(
        [string]$RepoUrl,
        [string]$Branch = "main"
    )

    # 读取现有配置或创建新配置
    if (Test-Path $script:CONFIG_FILE) {
        $config = Get-Content $script:CONFIG_FILE | ConvertFrom-Json
    }
    else {
        $config = @{}
    }

    # 更新 sync 配置
    $config.sync = @{
        repoUrl = $RepoUrl
        branch = $Branch
        lastSync = $null
    }

    # 保存配置
    $config | ConvertTo-Json -Depth 10 | Set-Content $script:CONFIG_FILE -Encoding UTF8
}
```

**Step 3: 验证函数**

运行: `pwsh -NoProfile -Command ". ./cc.ps1; Set-SyncConfig -RepoUrl 'git@github.com:test/repo.git'; Get-SyncConfig"`

**Step 4: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加同步配置读写函数"
```

---

## Task 4: 实现交互式配置初始化

**Files:**
- Modify: `cc.ps1` (在 `Set-SyncConfig` 函数后)

**Step 1: 添加 Initialize-SyncConfig 函数**

```powershell
# 初始化同步配置（交互式）
function Initialize-SyncConfig {
    Write-Host ""
    Write-Host "正在初始化同步配置..." -ForegroundColor Cyan
    Write-Host ""

    # 输入仓库 URL
    Write-Host "请输入 Git 仓库 URL (SSH 格式): " -NoNewline
    $repoUrl = Read-Host

    if (-not $repoUrl) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 仓库 URL 不能为空" -ForegroundColor Red
        Write-Host ""
        return $null
    }

    # 输入分支名称
    Write-Host "分支名称 [main]: " -NoNewline
    $branch = Read-Host
    if (-not $branch) {
        $branch = "main"
    }

    # 保存配置
    Set-SyncConfig -RepoUrl $repoUrl -Branch $branch

    Write-Host ""
    Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置已保存" -ForegroundColor Green
    Write-Host ""

    return @{
        repoUrl = $repoUrl
        branch = $branch
    }
}
```

**Step 2: 验证函数**

运行: `pwsh -NoProfile -Command ". ./cc.ps1; Initialize-SyncConfig"` (手动输入测试)

**Step 3: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加交互式配置初始化"
```

---

## Task 5: 实现时间戳比较和合并逻辑

**Files:**
- Modify: `cc.ps1` (在 `Initialize-SyncConfig` 函数后)

**Step 1: 添加 Merge-Profiles 函数**

```powershell
# 比较并合并 profiles
function Merge-Profiles {
    param(
        [string]$LocalDir,
        [string]$RemoteDir,
        [string]$Mode = "sync"  # sync, push, pull
    )

    $results = @{
        uploaded = @()
        downloaded = @()
        skipped = @()
    }

    # 获取本地和远程文件列表
    $localFiles = @{}
    $remoteFiles = @{}

    if (Test-Path "$LocalDir/*.json") {
        Get-ChildItem "$LocalDir/*.json" | ForEach-Object {
            $content = Get-Content $_.FullName | ConvertFrom-Json
            $localFiles[$_.Name] = @{
                path = $_.FullName
                updatedAt = $content.updatedAt
            }
        }
    }

    if (Test-Path "$RemoteDir/*.json") {
        Get-ChildItem "$RemoteDir/*.json" | ForEach-Object {
            $content = Get-Content $_.FullName | ConvertFrom-Json
            $remoteFiles[$_.Name] = @{
                path = $_.FullName
                updatedAt = $content.updatedAt
            }
        }
    }

    # 合并逻辑
    $allFiles = @{}
    $localFiles.Keys | ForEach-Object { $allFiles[$_] = $true }
    $remoteFiles.Keys | ForEach-Object { $allFiles[$_] = $true }

    foreach ($fileName in $allFiles.Keys) {
        $local = $localFiles[$fileName]
        $remote = $remoteFiles[$fileName]

        if ($Mode -eq "push") {
            # 仅上传模式
            if ($local -and -not $remote) {
                Copy-Item $local.path "$RemoteDir/$fileName"
                $results.uploaded += $fileName
            }
            elseif ($local -and $remote) {
                if ($local.updatedAt -gt $remote.updatedAt) {
                    Copy-Item $local.path "$RemoteDir/$fileName"
                    $results.uploaded += $fileName
                }
                else {
                    $results.skipped += $fileName
                }
            }
        }
        elseif ($Mode -eq "pull") {
            # 仅下载模式
            if ($remote -and -not $local) {
                Copy-Item $remote.path "$LocalDir/$fileName"
                $results.downloaded += $fileName
            }
            elseif ($local -and $remote) {
                if ($remote.updatedAt -gt $local.updatedAt) {
                    Copy-Item $remote.path "$LocalDir/$fileName"
                    $results.downloaded += $fileName
                }
                else {
                    $results.skipped += $fileName
                }
            }
        }
        else {
            # 双向同步模式
            if ($local -and -not $remote) {
                Copy-Item $local.path "$RemoteDir/$fileName"
                $results.uploaded += $fileName
            }
            elseif (-not $local -and $remote) {
                Copy-Item $remote.path "$LocalDir/$fileName"
                $results.downloaded += $fileName
            }
            elseif ($local -and $remote) {
                if ($local.updatedAt -gt $remote.updatedAt) {
                    Copy-Item $local.path "$RemoteDir/$fileName"
                    $results.uploaded += $fileName
                }
                elseif ($remote.updatedAt -gt $local.updatedAt) {
                    Copy-Item $remote.path "$LocalDir/$fileName"
                    $results.downloaded += $fileName
                }
                else {
                    $results.skipped += $fileName
                }
            }
        }
    }

    return $results
}
```

**Step 2: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加 profiles 合并逻辑"
```

---

## Task 6: 实现主同步函数

**Files:**
- Modify: `cc.ps1` (在 `Merge-Profiles` 函数后)

**Step 1: 添加 Sync-Profiles 函数**

```powershell
# 同步 profiles 到/从远程仓库
function Sync-Profiles {
    param([string]$Mode = "sync")

    # 检查环境
    if (-not (Test-SyncEnvironment)) {
        return
    }

    # 获取或初始化配置
    $config = Get-SyncConfig
    if (-not $config) {
        $config = Initialize-SyncConfig
        if (-not $config) {
            return
        }
    }

    Write-Host ""
    Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 仓库: $($config.repoUrl)" -ForegroundColor Green
    Write-Host "正在同步..." -ForegroundColor Cyan

    # 创建临时目录
    $tempDir = New-TemporaryDirectory

    try {
        # Clone 仓库
        $cloneResult = git clone --depth 1 --branch $config.branch $config.repoUrl $tempDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 克隆仓库失败" -ForegroundColor Red
            Write-Host "  $cloneResult" -ForegroundColor Yellow
            Write-Host ""
            return
        }

        # 确保 profiles 目录存在
        $remoteProfilesDir = "$tempDir/profiles"
        if (-not (Test-Path $remoteProfilesDir)) {
            New-Item -ItemType Directory -Path $remoteProfilesDir -Force | Out-Null
        }

        # 执行合并
        $results = Merge-Profiles -LocalDir $script:PROFILES_DIR -RemoteDir $remoteProfilesDir -Mode $Mode

        # 检查是否有变更
        Push-Location $tempDir
        try {
            $hasChanges = (git status --porcelain).Length -gt 0

            if ($hasChanges) {
                # 配置 git 用户信息
                git config user.email "cc-helper@local" 2>$null
                git config user.name "cc-helper" 2>$null

                # 提交变更
                git add .
                git commit -m "sync profiles at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

                # 推送
                $pushResult = git push 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host ""
                    Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 推送失败" -ForegroundColor Red
                    Write-Host "  $pushResult" -ForegroundColor Yellow
                    Write-Host ""
                    return
                }
            }
        }
        finally {
            Pop-Location
        }

        # 显示结果
        Write-Host ""
        if ($results.uploaded.Count -gt 0) {
            foreach ($f in $results.uploaded) {
                Write-Host "  $($ANSI.Green)↑$($ANSI.Reset) 上传: $f"
            }
        }
        if ($results.downloaded.Count -gt 0) {
            foreach ($f in $results.downloaded) {
                Write-Host "  $($ANSI.Cyan)↓$($ANSI.Reset) 下载: $f"
            }
        }
        if ($results.skipped.Count -gt 0) {
            foreach ($f in $results.skipped) {
                Write-Host "  $($ANSI.DarkGray)=$($ANSI.Reset) 跳过: $f (无变化)"
            }
        }

        # 更新最后同步时间
        Update-SyncLastTime

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 同步完成" -ForegroundColor Green
        Write-Host ""
    }
    finally {
        # 清理临时目录
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 创建临时目录的辅助函数
function New-TemporaryDirectory {
    $tempPath = [System.IO.Path]::GetTempPath()
    $tempDir = Join-Path $tempPath "cc-sync-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    return $tempDir
}

# 更新最后同步时间
function Update-SyncLastTime {
    if (Test-Path $script:CONFIG_FILE) {
        $config = Get-Content $script:CONFIG_FILE | ConvertFrom-Json
        $config.sync.lastSync = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $config | ConvertTo-Json -Depth 10 | Set-Content $script:CONFIG_FILE -Encoding UTF8
    }
}
```

**Step 2: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加主同步函数"
```

---

## Task 7: 更新帮助信息和添加命令入口

**Files:**
- Modify: `cc.ps1:84-94` (Show-Help 函数)
- Modify: `cc.ps1:534-546` (switch 语句)

**Step 1: 更新 Show-Help 函数**

在 `cc update` 行后添加：

```powershell
    Write-Host "  cc sync [push|pull] 同步配置到/从远程仓库"
```

**Step 2: 添加 switch 分支**

在 `default` 行前添加：

```powershell
    'sync' { Sync-Profiles -Mode $param }
```

**Step 3: 验证帮助信息**

运行: `pwsh -NoProfile -File ./cc.ps1`

**Step 4: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 添加 sync 命令入口和帮助信息"
```

---

## Task 8: 为 New-Profile 添加 updatedAt 字段

**Files:**
- Modify: `cc.ps1:136-147` (New-Profile 函数)

**Step 1: 在保存配置前添加 updatedAt**

修改 `New-Profile` 函数，在 `$result | ConvertTo-Json` 前添加：

```powershell
        # 添加时间戳
        $result | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") -Force
```

**Step 2: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 为新配置添加 updatedAt 时间戳"
```

---

## Task 9: 为 Edit-Profile 更新 updatedAt 字段

**Files:**
- Modify: `cc.ps1` (Edit-Profile 函数保存部分)

**Step 1: 找到 Edit-Profile 保存配置的位置并更新**

在保存编辑后的配置前添加 updatedAt 更新。

**Step 2: Commit**

```bash
git add cc.ps1
git commit -m "feat(sync): 编辑配置时更新 updatedAt 时间戳"
```

---

## Task 10: 集成测试

**Step 1: 测试帮助信息**

运行: `pwsh -NoProfile -File ./cc.ps1`

预期: 显示包含 `cc sync` 的帮助信息

**Step 2: 测试配置初始化**

准备一个测试仓库，运行: `pwsh -NoProfile -File ./cc.ps1 sync`

预期: 提示输入仓库 URL 和分支

**Step 3: 测试同步功能**

创建测试配置后运行同步，验证双向同步逻辑。

**Step 4: 最终 Commit**

```bash
git add -A
git commit -m "feat(sync): 完成 cc sync 命令实现"
```
