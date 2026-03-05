# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

cc 是 Claude Code 配置管理工具，使用 PowerShell 7.0 编写，用于管理多个 Claude Code API 配置文件。

## 常用命令

```powershell
# 显示帮助信息
cc

# 切换配置并启动 Claude Code
cc use [alias]           # 直接切换
cc use [alias] [args...] # 切换并传递额外参数给 claude（如 -c "查询"）
cc use                   # 显示选择器

# 列出所有配置
cc list
cc ls

# 创建新配置
cc new

# 编辑配置
cc edit [alias]

# 删除配置
cc rm [alias]

# 测试 API 连接
cc test [alias]

# 从 cc-switch 迁移
cc ccswitch

# 同步配置到远程仓库
cc sync push
cc sync pull

# 卸载 cc
cc uninstall

# 更新 cc
cc update
```

## 代码架构

### 主要文件

- **cc.ps1** (~1075行) - 主入口脚本，包含所有核心功能函数和命令处理
- **tui.ps1** (~850行) - TUI 界面模块，提供选择器、表单等交互功能，定义 ANSI 转义序列常量
- **ccswitch.ps1** - 从 cc-switch 迁移配置的功能模块
- **install.ps1** - 安装脚本
- **update.ps1** - 更新脚本

### 命令入口

主入口在 `cc.ps1` 底部（约第1058-1074行），通过 `switch` 语句根据 `$args[0]` 分发到不同函数：

- `use` → `Use-Profile`
- `list`/`ls` → `Show-List`
- `new` → `New-Profile`
- `edit` → `Edit-Profile`
- `rm` → `Remove-Profile`
- `test` → `Test-Profile`
- `ccswitch` → `Import-FromCcSwitch`
- `uninstall` → `Uninstall-Cc`
- `sync` → `Sync-Profiles`

### TUI 模块 (tui.ps1)

提供交互式界面组件：
- `Show-ProfileSelector` - 配置选择器（上下键选择）
- `Show-MultiSelectSelector` - 多选选择器
- `Show-ConfigForm` - 配置表单（创建/编辑配置）
- `Show-ModelInputForm` - 可选模型管理（添加/编辑/删除模型ID）
- `Show-ModelSelector` - 模型选择器（从可选模型列表选择）

表单字段定义在 `$script:FormFields` 数组中，支持 `IsArray=$true` 属性处理数组类型字段。

### 配置存储

- **配置目录**: `~/.cc/`
- **配置文件**: `~/.cc/profiles/*.json`
- **当前配置**: `~/.cc/current`
- **全局配置**: `~/.cc/config.json`
- **删除记录**: `~/.cc/deleted.json` - 记录已删除的配置，防止 sync pull 恢复

### 同步功能

`Sync-Profiles` 函数实现了配置的 Git 同步：
- 使用 `~/.cc/deleted.json` 记录已删除的配置名
- pull 时跳过已删除的配置，避免恢复
- push 时将删除记录同步到远程

## 开发说明

这是纯 PowerShell 脚本项目，无需构建或编译。修改后直接运行测试即可。

```powershell
# 语法检查
pwsh -NoProfile -Command "Get-Content cc.ps1 | ForEach-Object { [scriptblock]::Create($_) }" 2>$null; if ($?) { "OK" }

# 快速功能测试
. ./cc.ps1  # 在当前 shell 中加载函数，然后手动调用
```

## Code Quality Checklist

- After refactoring/extracting code, always run syntax validation and functional tests
- Double-check parameter names when calling existing functions (avoid typos like skipDangerousModePermissionPrompt)
- Verify numeric comparisons use correct thresholds (e.g., -gt 0 vs -gt 1 for non-empty checks)

## PowerShell Best Practices

- Use if/elseif structures instead of switch statements inside PowerShell classes (switch causes syntax issues)
- Always test keyboard navigation and window resize scenarios for TUI features
- Handle empty repository/missing branch scenarios in git operations

## Testing Requirements

- Test with edge cases: empty repositories, missing config properties, window resize events
- Verify save/load operations handle legacy configuration formats gracefully