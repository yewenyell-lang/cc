#!/usr/bin/env pwsh
# cc.ps1 - Claude Code 配置管理工具

#Requires -Version 7.0

# 导入 TUI 模块
. "$PSScriptRoot/tui.ps1"

# 配置目录
$script:CC_DIR = "$env:USERPROFILE/.cc"
$script:PROFILES_DIR = "$script:CC_DIR/profiles"
$script:CURRENT_FILE = "$script:CC_DIR/current"
$script:CONFIG_FILE = "$script:CC_DIR/config.json"

# 更新源配置
$script:UPDATE_SOURCES = @{
    github = "https://raw.githubusercontent.com/yewenyell-lang/cc/main/update.ps1"
    gitee = "https://gitee.com/yell-run/cc/raw/main/update.ps1"
}

# 导入 cc-switch 迁移模块
. "$PSScriptRoot/ccswitch.ps1"

# 确保配置目录存在
function Ensure-ConfigDir {
    if (-not (Test-Path $script:PROFILES_DIR)) {
        New-Item -ItemType Directory -Path $script:PROFILES_DIR -Force | Out-Null
    }
}

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

# 初始化同步配置（交互式）
function Initialize-SyncConfig {
    Write-Host ""
    Write-Host "正在初始化同步配置..." -ForegroundColor Cyan
    Write-Host ""

    # 输入仓库 URL
    Write-Host "请输入 Git 仓库 URL (支持 HTTPS 或 SSH 格式): " -NoNewline
    $repoUrl = Read-Host

    if (-not $repoUrl) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 仓库 URL 不能为空" -ForegroundColor Red
        Write-Host ""
        return $null
    }

    # 验证 URL 格式
    $isHttps = $repoUrl -match '^https?://'
    $isSsh = $repoUrl -match '^git@|\.git$'
    if (-not $isHttps -and -not $isSsh) {
        Write-Host ""
        Write-Host "$($ANSI.Yellow)!$($ANSI.Reset) URL 格式可能不正确，继续吗？" -ForegroundColor Yellow
        Write-Host "  HTTPS 格式: https://github.com/owner/repo.git"
        Write-Host "  SSH 格式:   git@github.com:owner/repo.git"
        Write-Host ""
        Write-Host "继续 [Y/n]: " -NoNewline
        $confirm = Read-Host
        if ($confirm -eq 'n' -or $confirm -eq 'N') {
            return $null
        }
    }

    # HTTPS 提示
    if ($isHttps) {
        Write-Host ""
        Write-Host "$($ANSI.Cyan)ℹ$($ANSI.Reset) 使用 HTTPS 格式，请确保已配置 Git credential helper" -ForegroundColor Cyan
        Write-Host "  或在 URL 中包含 token: https://<token>@github.com/owner/repo.git" -ForegroundColor DarkGray
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

# 删除记录文件路径
$script:DELETED_FILE = "$script:CC_DIR/deleted.json"

# 上次同步 commit 记录文件路径
$script:LAST_SYNC_COMMIT_FILE = "$script:CC_DIR/last_sync_commit"

# 获取删除记录
function Get-DeletedRecords {
    if (-not (Test-Path $script:DELETED_FILE)) {
        return @()
    }

    try {
        $records = Get-Content $script:DELETED_FILE | ConvertFrom-Json
        return $records
    }
    catch {
        return @()
    }
}

# 添加删除记录
function Add-DeletedRecord {
    param([string]$ProfileName)

    $records = @(Get-DeletedRecords)
    if ($records -notcontains $ProfileName) {
        $records += $ProfileName
        $records | ConvertTo-Json | Set-Content $script:DELETED_FILE -Encoding UTF8
    }
}

# 从删除记录中移除
function Remove-DeletedRecord {
    param([string]$ProfileName)

    $records = @(Get-DeletedRecords)
    $records = $records | Where-Object { $_ -ne $ProfileName }

    if ($records.Count -gt 0) {
        $records | ConvertTo-Json | Set-Content $script:DELETED_FILE -Encoding UTF8
    }
    elseif (Test-Path $script:DELETED_FILE) {
        Remove-Item $script:DELETED_FILE -Force
    }
}

# 比较并合并 profiles
function Merge-Profiles {
    param(
        [string]$LocalDir,
        [string]$RemoteDir,
        [string]$Mode = "sync",  # sync, push, pull
        [string[]]$DeletedFromGit = @()  # git diff 检测到的删除文件
    )

    $results = @{
        uploaded = @()
        downloaded = @()
        skipped = @()
        deleted = @()
    }

    # 加载删除记录
    $deletedRecords = @(Get-DeletedRecords)

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
                $profileName = $fileName -replace '\.json$', ''
                if ($deletedRecords -contains $profileName) {
                    # 已被本地删除，跳过下载
                    $results.skipped += "$fileName (已删除)"
                }
                else {
                    Copy-Item $remote.path "$LocalDir/$fileName"
                    $results.downloaded += $fileName
                }
            }
            # 删除检测由 git diff 处理，不再通过文件存在性判断
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
                $profileName = $fileName -replace '\.json$', ''
                if ($deletedRecords -contains $profileName) {
                    # 已被本地删除，删除远程文件并移除记录
                    Remove-Item $remote.path -Force
                    Remove-DeletedRecord -ProfileName $profileName
                    $results.deleted += $fileName
                }
                else {
                    Copy-Item $remote.path "$LocalDir/$fileName"
                    $results.downloaded += $fileName
                }
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

    # pull 模式：处理 git diff 检测到的删除
    if ($Mode -eq "pull" -and $DeletedFromGit.Count -gt 0) {
        foreach ($deletedPath in $DeletedFromGit) {
            $fileName = Split-Path $deletedPath -Leaf
            $localPath = "$LocalDir/$fileName"

            if (Test-Path $localPath) {
                $profileName = $fileName -replace '\.json$', ''
                Remove-Item $localPath -Force
                Remove-DeletedRecord -ProfileName $profileName
                $results.deleted += "$fileName (远程已删除)"
            }
        }
    }

    return $results
}

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
        $cloneFailed = $LASTEXITCODE -ne 0
        $isEmptyRepo = $cloneResult -match "Remote branch.*not found"

        if ($cloneFailed) {
            if ($isEmptyRepo) {
                # 空仓库，初始化本地仓库
                Write-Host "  检测到空仓库，正在初始化..." -ForegroundColor Yellow

                Push-Location $tempDir
                try {
                    git init 2>&1 | Out-Null
                    git remote add origin $config.repoUrl 2>&1 | Out-Null
                    git checkout -b $config.branch 2>&1 | Out-Null
                }
                finally {
                    Pop-Location
                }
            }
            else {
                Write-Host ""
                Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 克隆仓库失败" -ForegroundColor Red
                Write-Host "  $cloneResult" -ForegroundColor Yellow
                Write-Host ""
                return
            }
        }

        # 确保 profiles 目录存在
        $remoteProfilesDir = "$tempDir/profiles"
        if (-not (Test-Path $remoteProfilesDir)) {
            New-Item -ItemType Directory -Path $remoteProfilesDir -Force | Out-Null
        }

        # pull 模式：通过 git diff 检测删除的文件
        $deletedFromGit = @()
        $currentCommit = $null
        if ($Mode -eq "pull" -and -not $isEmptyRepo) {
            # 读取上次同步的 commit
            $lastSyncCommit = $null
            if (Test-Path $script:LAST_SYNC_COMMIT_FILE) {
                $lastSyncCommit = (Get-Content $script:LAST_SYNC_COMMIT_FILE -Raw).Trim()
            }

            # 获取当前 commit hash
            Push-Location $tempDir
            try {
                $currentCommit = git rev-parse HEAD 2>$null

                if ($lastSyncCommit -and $currentCommit) {
                    # 尝试获取更多历史（浅克隆需要）
                    git fetch --unshallow 2>$null
                    git fetch --depth=1000 2>$null

                    # 检测 profiles/ 目录下被删除的文件
                    $diffOutput = git diff --name-status --diff-filter=D "$lastSyncCommit" "$currentCommit" -- "profiles/*.json" 2>$null
                    if ($diffOutput) {
                        $deletedFromGit = $diffOutput | Where-Object { $_ -match '^D\s+' } | ForEach-Object { ($_ -split '\s+')[-1] }
                    }
                }
            }
            finally {
                Pop-Location
            }
        }

        # 执行合并
        $results = Merge-Profiles -LocalDir $script:PROFILES_DIR -RemoteDir $remoteProfilesDir -Mode $Mode -DeletedFromGit $deletedFromGit

        # 检查是否有变更
        Push-Location $tempDir
        try {
            $hasChanges = (git status --porcelain).Length -gt 0

            if ($hasChanges) {
                # 配置 git 用户信息
                git config user.email "cc@local" 2>$null
                git config user.name "cc" 2>$null

                # 提交变更
                git add .
                git commit -m "sync profiles at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

                # 推送
                if ($isEmptyRepo) {
                    # 空仓库首次推送，设置上游分支
                    $pushResult = git push -u origin $config.branch 2>&1
                }
                else {
                    $pushResult = git push 2>&1
                }
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

        # push/sync 模式完成后保存当前 commit
        if ($Mode -in @("push", "sync") -and -not $isEmptyRepo) {
            Push-Location $tempDir
            try {
                $commitToSave = git rev-parse HEAD 2>$null
                if ($commitToSave) {
                    $commitToSave | Out-File $script:LAST_SYNC_COMMIT_FILE -Force -Encoding UTF8
                }
            }
            finally {
                Pop-Location
            }
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
        if ($results.deleted.Count -gt 0) {
            foreach ($f in $results.deleted) {
                Write-Host "  $($ANSI.Red)✗$($ANSI.Reset) 删除: $f" -ForegroundColor Red
            }
        }

        # 更新最后同步时间
        Update-SyncLastTime

        # pull 模式完成后保存当前 commit（如果没有变更则使用之前获取的 commit）
        if ($Mode -eq "pull" -and $currentCommit) {
            $currentCommit | Out-File $script:LAST_SYNC_COMMIT_FILE -Force -Encoding UTF8
        }

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

    # 将当前配置排在最前面
    $profiles = $profiles | Sort-Object { -($_.isCurrent -as [int]) }
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
    Write-Host "  cc uninstall    卸载 cc"
    Write-Host "  cc update [github|gitee] 更新 cc 到最新版本"
    Write-Host "  cc sync [push|pull] 同步配置到/从远程仓库"
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

        # 检查是否有可选模型列表
        $extraModels = ""
        if ($p.config.env.PSObject.Properties.Name -contains 'ANTHROPIC_MODELS') {
            $modelsJson = $p.config.env.ANTHROPIC_MODELS
            if ($modelsJson) {
                try {
                    $models = $modelsJson | ConvertFrom-Json
                    if ($models -is [String]) {
                        $models = @($models)
                    }
                    if ($models.Count -gt 1) {
                        # 获取除了当前模型以外的其他模型
                        $otherModels = $models | Where-Object { $_ -ne $model }
                        if ($otherModels.Count -gt 0) {
                            $extraModels = " $($ANSI.DarkGray)[$($otherModels -join ", ")]$($ANSI.Reset)"
                        }
                    }
                } catch {}
            }
        }

        Write-Host "  $alias $name $model$extraModels $currentMark"
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
        # 处理 models 数组，保存到环境变量
        $envVars = @{}
        foreach ($key in $result.env.Keys) {
            $envVars[$key] = $result.env[$key]
        }
        if ($result.models -and $result.models.Count -gt 0) {
            $envVars['ANTHROPIC_MODELS'] = ($result.models | ConvertTo-Json)
        }

        # 构建保存对象
        $profileData = @{
            alias = $result.alias
            name = $result.name
            skipDangerousModePermissionPrompt = $true
            env = $envVars
        }
        $profileData | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") -Force

        $profilePath = "$script:PROFILES_DIR/$($result.alias).json"
        $profileData | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$($result.alias)' 创建成功" -ForegroundColor Green
        Write-Host ""
    }
}

# 切换配置并启动 Claude Code
function Use-Profile {
    param(
        [string]$Alias,
        [string[]]$ExtraArgs
    )

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


    # 直接使用配置中的默认模型，不再弹出选择器

    # 生成临时配置文件
    $tempPath = [System.IO.Path]::GetTempFileName() + ".json"
    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8

        # 更新当前配置
        Set-CurrentAlias -Alias $Alias

        # 清空屏幕，只保留启动提示
        Clear-Host

        # 构建并显示完整命令
        $displayParts = @("claude", "--settings `"$tempPath`"", "--dangerously-skip-permissions")
        if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
            foreach ($arg in $ExtraArgs) {
                if ($arg -match '\s') {
                    $displayParts += "`"$arg`""
                } else {
                    $displayParts += $arg
                }
            }
        }
        Write-Host "启动 Claude Code (配置: $Alias)" -ForegroundColor Cyan
        Write-Host "命令: $($displayParts -join ' ')" -ForegroundColor DarkGray
        Write-Host ""

        & claude --settings $tempPath --dangerously-skip-permissions @ExtraArgs
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
            ANTHROPIC_MODELS = $existingConfig.env.ANTHROPIC_MODELS
        }
    }

    $existingAliases = $profiles | ForEach-Object { $_.alias }
    $result = Show-ConfigForm -ExistingConfig $existingHashtable -IsEdit -ExistingAliases $existingAliases

    if ($result) {
        # 保存配置(使用原别名)
        $result.alias = $Alias

        # 处理 models 数组，保存到环境变量
        $envVars = @{}
        foreach ($key in $result.env.Keys) {
            $envVars[$key] = $result.env[$key]
        }
        if ($result.models -and $result.models.Count -gt 0) {
            $envVars['ANTHROPIC_MODELS'] = ($result.models | ConvertTo-Json)
        }

        # 构建保存对象
        $profileData = @{
            alias = $result.alias
            name = $result.name
            skipDangerousModePermissionPrompt = $true
            env = $envVars
        }
        $profileData | Add-Member -NotePropertyName "updatedAt" -NotePropertyValue (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") -Force

        $profileData | ConvertTo-Json -Depth 10 | Set-Content $profilePath -Encoding UTF8

        Write-Host ""
        Write-Host "$($ANSI.Green)✓$($ANSI.Reset) 配置 '$Alias' 已更新" -ForegroundColor Green
        Write-Host ""
    }
}

# 从远程仓库删除配置
function Remove-RemoteProfile {
    param([string]$ProfileName)

    # 检查环境
    if (-not (Test-SyncEnvironment)) {
        return "error"
    }

    # 获取同步配置
    $config = Get-SyncConfig
    if (-not $config) {
        return "not_configured"
    }

    # 创建临时目录
    $tempDir = New-TemporaryDirectory

    try {
        # Clone 仓库
        $cloneResult = git clone --depth 1 --branch $config.branch $config.repoUrl $tempDir 2>&1
        $cloneFailed = $LASTEXITCODE -ne 0
        $isEmptyRepo = $cloneResult -match "Remote branch.*not found"

        if ($cloneFailed -and -not $isEmptyRepo) {
            Write-Host "  $($ANSI.BrightRed)✗$($ANSI.Reset) 克隆仓库失败" -ForegroundColor Red
            return "error"
        }

        # 检查远程是否存在该配置文件
        $remoteProfilePath = "$tempDir/profiles/$ProfileName.json"
        if (-not (Test-Path $remoteProfilePath)) {
            return "not_found"
        }

        # 删除文件
        Remove-Item $remoteProfilePath -Force

        # 提交并推送
        Push-Location $tempDir
        try {
            git config user.email "cc@local" 2>$null
            git config user.name "cc" 2>$null
            git add . 2>$null
            git commit -m "delete profile: $ProfileName" 2>$null

            if ($isEmptyRepo) {
                $pushResult = git push -u origin $config.branch 2>&1
            } else {
                $pushResult = git push 2>&1
            }

            if ($LASTEXITCODE -ne 0) {
                Write-Host "  $($ANSI.BrightRed)✗$($ANSI.Reset) 推送失败: $pushResult" -ForegroundColor Red
                return "error"
            }

            return "success"
        }
        finally {
            Pop-Location
        }
    }
    catch {
        Write-Host "  $($ANSI.BrightRed)✗$($ANSI.Reset) 远程删除失败: $_" -ForegroundColor Red
        return "error"
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
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
        # 先尝试从远程删除
        $remoteResult = Remove-RemoteProfile -ProfileName $Alias

        switch ($remoteResult) {
            "success" {
                Write-Host "  $($ANSI.Green)✓$($ANSI.Reset) 已从远程删除" -ForegroundColor Green
            }
            "not_configured" {
                Write-Host "  $($ANSI.Yellow)!$($ANSI.Reset) 未配置同步，仅删除本地" -ForegroundColor Yellow
            }
            "not_found" {
                Write-Host "  $($ANSI.Yellow)!$($ANSI.Reset) 远程不存在该配置" -ForegroundColor Yellow
            }
            "error" {
                Write-Host ""
                Write-Host "  $($ANSI.BrightRed)✗$($ANSI.Reset) 远程删除失败" -ForegroundColor Red
                Write-Host "  继续删除本地? (y/N): " -NoNewline -ForegroundColor Yellow
                $continueLocal = Read-Host
                if ($continueLocal -ne 'y' -and $continueLocal -ne 'Y') {
                    Write-Host ""
                    Write-Host "  已取消" -ForegroundColor DarkGray
                    Write-Host ""
                    return
                }
            }
        }

        # 删除本地配置
        Remove-Item $profilePath -Force

        # 如果删除的是当前配置，清除 current 文件
        if ($Alias -eq $currentAlias) {
            Remove-Item $script:CURRENT_FILE -Force -ErrorAction SilentlyContinue
        }

        # 记录删除操作，防止 sync 恢复
        Add-DeletedRecord -ProfileName $Alias

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

# 卸载 cc
function Uninstall-Cc {
    param([string[]]$Args)

    $uninstallScript = "$PSScriptRoot/uninstall.ps1"

    if (-not (Test-Path $uninstallScript)) {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 卸载脚本不存在: $uninstallScript" -ForegroundColor Red
        Write-Host "请直接运行: pwsh -NoProfile -ExecutionPolicy Bypass -File `$env:USERPROFILE\.cc\uninstall.ps1" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "即将启动卸载脚本..." -ForegroundColor Cyan
    Write-Host ""

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $uninstallScript @Args
}

# 获取全局配置
function Get-GlobalConfig {
    if (Test-Path $script:CONFIG_FILE) {
        try {
            return Get-Content $script:CONFIG_FILE | ConvertFrom-Json
        } catch {
            return @{}
        }
    }
    return @{}
}

# 保存更新源配置
function Set-UpdateSource {
    param([string]$Source)
    $config = Get-GlobalConfig
    $config | Add-Member -NotePropertyName 'updateSource' -NotePropertyValue $Source -Force
    $config | ConvertTo-Json -Depth 10 | Set-Content $script:CONFIG_FILE -Encoding UTF8
}

# 选择更新源
function Select-UpdateSource {
    Write-Host ""
    Write-Host "请选择更新源:" -ForegroundColor Cyan
    Write-Host "  1. GitHub (推荐)"
    Write-Host "  2. Gitee (国内镜像)"
    Write-Host ""

    while ($true) {
        $choice = Read-Host "请输入选项 (1/2)"
        switch ($choice) {
            '1' {
                Set-UpdateSource -Source 'github'
                return 'github'
            }
            '2' {
                Set-UpdateSource -Source 'gitee'
                return 'gitee'
            }
            default {
                Write-Host "无效选项，请重新输入" -ForegroundColor Red
            }
        }
    }
}

# 更新 cc
function Update-Cc {
    param([string]$Source)

    # 确定更新源
    if ($Source -and $script:UPDATE_SOURCES.ContainsKey($Source)) {
        # 命令行指定了有效源
        $useSource = $Source
        Set-UpdateSource -Source $Source
    } else {
        # 读取已保存的源
        $config = Get-GlobalConfig
        $savedSource = $config.updateSource
        if ($savedSource -and $script:UPDATE_SOURCES.ContainsKey($savedSource)) {
            $useSource = $savedSource
        } else {
            # 没有保存的源，让用户选择
            $useSource = Select-UpdateSource
            if (-not $useSource) { return }
        }
    }

    # 执行更新
    $UPDATE_URL = $script:UPDATE_SOURCES[$useSource]
    Write-Host "正在更新 cc... (源: $useSource)" -ForegroundColor Cyan

    try {
        Invoke-WebRequest -Uri $UPDATE_URL -OutFile "$env:TEMP\cc-update.ps1" -ErrorAction Stop
        & "$env:TEMP\cc-update.ps1" -Source $useSource
        Remove-Item "$env:TEMP\cc-update.ps1" -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host ""
        Write-Host "$($ANSI.BrightRed)✗$($ANSI.Reset) 更新失败: $_" -ForegroundColor Red

        # 询问是否换源
        $otherSource = if ($useSource -eq 'github') { 'gitee' } else { 'github' }
        Write-Host ""
        $choice = Read-Host "是否切换到 $otherSource 重试? (y/n)"

        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Update-Cc -Source $otherSource
        } else {
            Write-Host ""
            Write-Host "手动更新命令:" -ForegroundColor Yellow
            Write-Host "  cc update github" -ForegroundColor Cyan
            Write-Host "  cc update gitee" -ForegroundColor Cyan
        }
    }
}

# 主入口
Ensure-ConfigDir

$command = $args[0]
$param = $args[1]

switch ($command) {
    $null { Show-Help }
    'use' {
        $extraArgs = if ($args.Count -gt 2) { $args[2..($args.Count-1)] } else { @() }
        Use-Profile -Alias $param -ExtraArgs $extraArgs
    }
    { $_ -in 'list', 'ls' } { Show-List }
    'new' { New-Profile }
    'edit' { Edit-Profile -Alias $param }
    'rm' { Remove-Profile -Alias $param }
    'test' { Test-Profile -Alias $param }
    'ccswitch' { Import-FromCcSwitch }
    'uninstall' { Uninstall-Cc -Args $args[1..($args.Length-1)] }
    'update' { Update-Cc -Source $param }
    'sync' { Sync-Profiles -Mode $param }
    default { Write-Host "未知命令: $command" -ForegroundColor Red; Show-Help }
}






