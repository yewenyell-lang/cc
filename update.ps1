#!/usr/bin/env pwsh
# update.ps1 - cc 更新脚本

param(
    [string]$LocalSourcePath = "",
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
    Write-Host "  -LocalSourcePath <路径>  从本地路径更新文件而不是从 GitHub 下载"
    Write-Host "  -Version                 显示版本信息"
    Write-Host "  -Help                    显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  update.ps1                          # 从 GitHub 更新到最新版本"
    Write-Host "  update.ps1 -LocalSourcePath .\cc   # 从本地目录更新"
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
        # 下载文件
        $BASE_URL = "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"
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
