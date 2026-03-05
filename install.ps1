#!/usr/bin/env pwsh
# install.ps1 - cc 一键安装脚本

param(
    [string]$LocalSourcePath = "",
    [string]$Source = "",
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
$BINDIR = "$env:USERPROFILE\.local\bin"
$CC_CMD = "$BINDIR\cc.cmd"

# 需要下载/复制的文件
$FILES = @("cc.ps1", "tui.ps1", "ccswitch.ps1")

# 下载源 URL
$DOWNLOAD_SOURCES = @{
    gitee = "https://gitee.com/yell-run/cc/raw/main"
    github = "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"
}

# 下载源优先级（用于自动切换）
$SOURCE_PRIORITY = @("gitee", "github")

# 显示版本信息
if ($Version) {
    Write-Host "cc install script v$SCRIPT_VERSION"
    exit 0
}

# 显示帮助信息
if ($Help) {
    Write-Host "cc 一键安装脚本 v$SCRIPT_VERSION"
    Write-Host ""
    Write-Host "用法: install.ps1 [选项]"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -LocalSourcePath <路径>  从本地路径复制文件而不是下载"
    Write-Host "  -Source <gitee|github>   指定下载源（默认自动选择：gitee -> github）"
    Write-Host "  -Version                 显示版本信息"
    Write-Host "  -Help                    显示此帮助信息"
    Write-Host ""
    Write-Host "下载源说明:"
    Write-Host "  gitee   - 从 Gitee 下载（国内网络推荐）"
    Write-Host "  github  - 从 GitHub 下载（国外网络推荐）"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  install.ps1                          # 自动选择源安装"
    Write-Host "  install.ps1 -Source github           # 从 GitHub 安装"
    Write-Host "  install.ps1 -LocalSourcePath .\cc   # 从本地目录安装"
    exit 0
}

# 检查 PowerShell 版本
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "错误: 需要 PowerShell 7.0 或更高版本" -ForegroundColor Red
    Write-Host "当前版本: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

Write-Host "开始安装 cc..." -ForegroundColor Cyan

# 创建目录
if (-not (Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    Write-Host "创建目录: $INSTALL_DIR" -ForegroundColor Green
}

if (-not (Test-Path $BINDIR)) {
    New-Item -ItemType Directory -Path $BINDIR -Force | Out-Null
    Write-Host "创建目录: $BINDIR" -ForegroundColor Green
}

# 安装文件（从本地复制或下载）
if ($LocalSourcePath -and (Test-Path $LocalSourcePath)) {
    Write-Host "使用本地源: $LocalSourcePath" -ForegroundColor Cyan
    foreach ($file in $FILES) {
        $src = Join-Path $LocalSourcePath $file
        $dest = "$INSTALL_DIR\$file"
        Write-Host "复制: $src -> $dest"
        try {
            Copy-Item -Path $src -Destination $dest -Force
            Write-Host "  完成" -ForegroundColor Green
        }
        catch {
            Write-Host "  失败: $_" -ForegroundColor Red
            exit 1
        }
    }
}
else {
    # 确定下载源
    if ($Source -and $DOWNLOAD_SOURCES.ContainsKey($Source)) {
        # 用户指定了有效的源
        $sourcesToTry = @($Source)
    } else {
        # 使用优先级列表（gitee 优先）
        $sourcesToTry = $SOURCE_PRIORITY
    }

    $downloadSuccess = $false
    foreach ($currentSource in $sourcesToTry) {
        $BASE_URL = $DOWNLOAD_SOURCES[$currentSource]
        Write-Host "尝试从 $currentSource 下载..." -ForegroundColor Cyan

        try {
            foreach ($file in $FILES) {
                $url = "$BASE_URL/$file"
                $dest = "$INSTALL_DIR\$file"
                Write-Host "下载: $url -> $dest"
                Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
                Write-Host "  完成" -ForegroundColor Green
            }
            $downloadSuccess = $true
            Write-Host "从 $currentSource 下载成功!" -ForegroundColor Green
            break
        }
        catch {
            Write-Host "  从 $currentSource 下载失败: $_" -ForegroundColor Yellow
            if ($sourcesToTry.IndexOf($currentSource) -lt $sourcesToTry.Length - 1) {
                Write-Host "切换到下一个源..." -ForegroundColor Cyan
            }
        }
    }

    if (-not $downloadSuccess) {
        Write-Host "错误: 所有下载源均失败" -ForegroundColor Red
        exit 1
    }
}

# 生成 uninstall.ps1
$uninstallScript = @"
param(
    [switch]`$Force,
    [switch]`$Version,
    [switch]`$Help
)

`$ErrorActionPreference = 'Stop'

`$SCRIPT_VERSION = "1.0.0"
`$INSTALL_DIR = "$INSTALL_DIR"
`$BINDIR = "$BINDIR"
`$CC_CMD = "$CC_CMD"

# 显示版本信息
if (`$Version) {
    Write-Host "cc uninstall script v`$SCRIPT_VERSION"
    exit 0
}

# 显示帮助信息
if (`$Help) {
    Write-Host "cc 卸载脚本 v`$SCRIPT_VERSION"
    Write-Host ""
    Write-Host "用法: uninstall.ps1 [选项]"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -Force     不询问确认，直接卸载"
    Write-Host "  -Version   显示版本信息"
    Write-Host "  -Help      显示此帮助信息"
    exit 0
}

Write-Host "警告: 将删除以下内容:" -ForegroundColor Yellow
Write-Host "  - `$INSTALL_DIR"
Write-Host "  - `$CC_CMD"
Write-Host ""

if (-not `$Force) {
    `$confirm = Read-Host "输入 'yes' 确认卸载"
    if (`$confirm -ne 'yes') {
        Write-Host "取消卸载" -ForegroundColor Cyan
        exit 0
    }
}

# 删除文件
if (Test-Path `$INSTALL_DIR) {
    Remove-Item -Path `$INSTALL_DIR -Recurse -Force
    Write-Host "已删除: `$INSTALL_DIR" -ForegroundColor Green
}

if (Test-Path `$CC_CMD) {
    Remove-Item -Path `$CC_CMD -Force
    Write-Host "已删除: `$CC_CMD" -ForegroundColor Green
}

Write-Host ""
Write-Host "卸载完成!" -ForegroundColor Green
Write-Host "如需从 PATH 中移除，请手动删除: `$env:USERPROFILE\.local\bin" -ForegroundColor Yellow
"@

$uninstallPath = "$INSTALL_DIR\uninstall.ps1"
Set-Content -Path $uninstallPath -Value $uninstallScript -Force
Write-Host "创建卸载脚本: $uninstallPath" -ForegroundColor Green

# 创建 cc.cmd
$cmdContent = @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.cc\cc.ps1" %*
"@

Set-Content -Path $CC_CMD -Value $cmdContent -Force
Write-Host "创建命令入口: $CC_CMD" -ForegroundColor Green

# 检查 PATH
$path = $env:PATH -split ';'
if ($path -notcontains $BINDIR) {
    Write-Host ""
    Write-Host "安装完成!" -ForegroundColor Green
    Write-Host ""
    Write-Host "请将以下路径添加到 PATH:" -ForegroundColor Yellow
    Write-Host "  $BINDIR"
    Write-Host ""
    Write-Host "方法: 系统属性 -> 高级 -> 环境变量 -> 用户变量 -> Path -> 编辑"
}
else {
    Write-Host ""
    Write-Host "安装完成!" -ForegroundColor Green
    Write-Host "运行 'cc --help' 开始使用"
}
