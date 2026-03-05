# cc-helper

Claude Code 配置管理工具 - 轻松管理多个 Claude Code API 配置。

## 功能特性

- 🎯 **多配置管理** - 创建和管理多个 API 配置文件
- 🔄 **快速切换** - 一键切换不同配置并启动 Claude Code
- ✅ **连接测试** - 测试 API 连接是否正常
- 📦 **一键安装** - 从 GitHub 快速安装
- 🗑️ **干净卸载** - 完整移除所有相关文件

## 安装

### 快速安装（推荐）

```powershell
irm https://raw.githubusercontent.com/yewenyell-lang/cc/main/install.ps1 | iex
```

### 本地安装

```powershell
git clone https://github.com/yewenyell-lang/cc.git
cd cc
pwsh -NoProfile -ExecutionPolicy Bypass -File  -LocalSourcePath .
```

### 安装后配置

安装完成后，请将以下路径添加到系统环境变量 `PATH` 中：

```
%USERPROFILE%\.local\bin
```

## 命令说明

| 命令 | 说明 |
|------|------|
| `cc` | 显示帮助信息和当前配置 |
| `cc use [alias]` | 切换配置并启动 Claude Code（无参数显示选择器） |
| `cc list`, `cc ls` | 列出所有配置 |
| `cc new` | 创建新配置 |
| `cc edit [alias]` | 编辑配置（无参数显示选择器） |
| `cc rm [alias]` | 删除配置（无参数显示选择器） |
| `cc test [alias]` | 测试 API 连接（无参数显示选择器） |
| `cc ccswitch` | 从 cc-switch 迁移配置 |
| `cc uninstall` | 卸载 cc-helper |

## 使用示例

### 创建新配置

```powershell
cc new
```

按提示输入：
- 配置别名（如：`myapi`）
- 显示名称
- API Token
- API 地址
- 模型配置

### 切换并启动

```powershell
# 显示选择器
cc use

# 直接切换到指定配置
cc use myapi
```

### 测试连接

```powershell
cc test myapi
```

### 卸载

```powershell
# 交互式卸载
cc uninstall

# 强制卸载（不询问确认）
cc uninstall -Force
```

## 配置目录

- **配置目录**: `~/.cc/`
- **配置文件**: `~/.cc/profiles/*.json`
- **当前配置**: `~/.cc/current`

## 系统要求

- Windows 10/11
- PowerShell 7.0 或更高版本

## 从 cc-switch 迁移

如果你之前使用过 cc-switch，可以使用以下命令迁移配置：

```powershell
cc ccswitch
```

## 许可证

MIT License
