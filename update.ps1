#!/usr/bin/env pwsh
# update.ps1 - cc 更新脚本

param(
    [string]$LocalSourcePath = "",
    [string]$Source = "github",
    [switch]$Version,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# 版本信息
$SCRIPT_VERSION = "1.0.0"

# 配置
$REPO_OWNER = "yewenyell-lang"
$REPO_NAME = "cc"
$INSTALL_DIR = "$env:USERPROFILE\.cc"

# 更新源 URL
$UPDATE_SOURCES = @{
    github = "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"
    gitee = "https://gitee.com/yell-run/cc/raw/main"
}

# 需要下载/复制的文件
$FILES = @("cc.ps1", "tui.ps1", "ccswitch.ps1")

# 显示版本信息
if ($Version) {
    Write-Host "cc update script v$SCRIPT_VERSION"
    exit 0
}

# 显示帮助信息
if ($Help) {
    Write-Host "cc 更新脚本 v$SCRIPT_VERSION"
    Write-Host ""
    Write-Host "用法: update.ps1 [选项]"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -LocalSourcePath <路径>  从本地路径更新文件而不是下载"
    Write-Host "  -Source <github|gitee>   指定更新源（默认读取 config.json 或 github）"
    Write-Host "  -Version                 显示版本信息"
    Write-Host "  -Help                    显示此帮助信息"
    Write-Host ""
    Write-Host "更新源说明:"
    Write-Host "  github  - 从 GitHub 更新（国外网络推荐）"
    Write-Host "  gitee   - 从 Gitee 更新（国内网络推荐）"
    Write-Host ""
    Write-Host "配置优先级:"
    Write-Host "  1. 命令行 -Source 参数"
    Write-Host "  2. ~/.cc/config.json 中的 updateSource"
    Write-Host "  3. 默认使用 github"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  update.ps1                          # 使用配置或默认源更新"
    Write-Host "  update.ps1 -Source gitee            # 从 Gitee 更新"
    Write-Host "  update.ps1 -LocalSourcePath .\cc    # 从本地目录更新"
    exit 0
}

# 检查是否已安装
if (-not (Test-Path $INSTALL_DIR)) {
    Write-Host "错误: 未检测到 cc 安装" -ForegroundColor Red
    Write-Host "请先运行 install.ps1 进行安装" -ForegroundColor Yellow
    exit 1
}

Write-Host "开始更新 cc..." -ForegroundColor Cyan

# 创建临时目录用于下载
$tempDir = Join-Path $env:TEMP "cc-update-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$backupFiles = @()

try {
    # 备份现有文件
    foreach ($file in $FILES) {
        $srcPath = Join-Path $INSTALL_DIR $file
        if (Test-Path $srcPath) {
            $bakPath = "$srcPath.bak"
            Copy-Item -Path $srcPath -Destination $bakPath -Force
            $backupFiles += $bakPath
            Write-Host "备份: $file" -ForegroundColor Gray
        }
    }

    # 更新文件（从本地复制或下载）
    if ($LocalSourcePath -and (Test-Path $LocalSourcePath)) {
        Write-Host "使用本地源: $LocalSourcePath" -ForegroundColor Cyan
        foreach ($file in $FILES) {
            $src = Join-Path $LocalSourcePath $file
            $dest = Join-Path $INSTALL_DIR $file
            Write-Host "复制: $src -> $dest"
            try {
                Copy-Item -Path $src -Destination $dest -Force
                Write-Host "  完成" -ForegroundColor Green
            }
            catch {
                throw "复制失败: $_"
            }
        }
    }
    else {
        # 尝试从全局配置读取更新源（向后兼容旧版 cc.ps1）
        $configPath = "$env:USERPROFILE\.cc\config.json"
        if (Test-Path $configPath) {
            try {
                $savedConfig = Get-Content $configPath -Raw | ConvertFrom-Json
                if ($savedConfig.updateSource -and $UPDATE_SOURCES.ContainsKey($savedConfig.updateSource)) {
                    $Source = $savedConfig.updateSource
                }
            } catch {
                # 忽略配置读取错误
            }
        }

        # 下载文件
        if (-not $UPDATE_SOURCES.ContainsKey($Source)) {
            $Source = "github"
        }
        $BASE_URL = $UPDATE_SOURCES[$Source]
        foreach ($file in $FILES) {
            $url = "$BASE_URL/$file"
            $tempPath = Join-Path $tempDir $file
            $dest = Join-Path $INSTALL_DIR $file
            Write-Host "下载: $url"
            try {
                Invoke-WebRequest -Uri $url -OutFile $tempPath -ErrorAction Stop
                Move-Item -Path $tempPath -Destination $dest -Force
                Write-Host "  更新: $file" -ForegroundColor Green
            }
            catch {
                throw "下载失败: $file - $_"
            }
        }
    }

    # 清理备份
    foreach ($bak in $backupFiles) {
        Remove-Item -Path $bak -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "✓ 更新完成!" -ForegroundColor Green
    Write-Host "运行 'cc --help' 查看新功能" -ForegroundColor Cyan
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
    Write-Host "✗ 更新失败: $_" -ForegroundColor Red
    Write-Host "已恢复备份" -ForegroundColor Yellow
    exit 1
}
finally {
    # 清理临时目录
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
