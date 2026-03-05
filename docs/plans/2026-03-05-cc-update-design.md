# cc update 命令设计

## 概述

在 cc.ps1 中新增 `update` 命令，从 GitHub 下载最新版本的 cc.ps1、tui.ps1、ccswitch.ps1 并覆盖本地文件，实现一键更新。

## 架构流程

```
cc update
  │
  ├── 1. 检查安装目录 ($env:USERPROFILE\.cc) 是否存在
  │     └── 不存在 → 提示"未安装，请先运行 install.ps1"
  │
  ├── 2. 下载最新文件 (raw.githubusercontent.com/yewenyell-lang/cc/main/)
  │     ├── cc.ps1
  │     ├── tui.ps1
  │     └── ccswitch.ps1
  │
  ├── 3. 备份当前文件 (*.ps1.bak)
  │
  ├── 4. 替换文件
  │
  └── 5. 显示结果
        ├── 成功 → "✓ 更新完成"
        └── 失败 → 恢复备份，提示"更新失败，请手动运行 install.ps1"
```

## 关键实现点

1. **下载源**: `https://raw.githubusercontent.com/yewenyell-lang/cc/main/{file}`
2. **备份机制**: 下载前将现有文件重命名为 `.bak`，失败时恢复
3. **错误处理**: 网络错误、文件不存在时保留旧文件并提示用户

## 帮助信息

在 Show-Help 函数中添加:

```powershell
Write-Host "  cc update      更新 cc-helper 到最新版本"
```

## 需要修改的文件

- `cc.ps1`: 添加 `Update-CcHelper` 函数和 switch 分支
