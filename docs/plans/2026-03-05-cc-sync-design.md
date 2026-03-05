# cc sync 命令设计

## 概述

在 cc.ps1 中新增 `sync` 命令，使用原生 git 命令将 profiles 配置同步到指定的私有 Git 仓库，支持多设备同步、备份恢复和团队共享。

## 功能特性

- 支持任意 Git 仓库（GitHub、GitLab、Gitea 等）
- 支持 HTTPS 和 SSH 两种认证方式
- 双向同步，按时间戳处理冲突
- 交互式初始化配置

## 命令设计

```
cc sync [push|pull]    同步配置到/从远程仓库
                       无参数时执行双向同步
                       push: 仅上传本地到远程
                       pull: 仅下载远程到本地
```

## 配置文件结构

**~/.cc/config.json** (新增)

```json
{
  "sync": {
    "repoUrl": "git@github.com:owner/repo.git",
    "branch": "main",
    "lastSync": "2026-03-05T10:00:00Z"
  }
}
```

## 架构流程

```
cc sync
  │
  ├── 1. 检查环境
  │     └── git 是否安装
  │
  ├── 2. 读取/初始化同步配置
  │     └── 无配置时提示输入仓库 URL
  │
  ├── 3. Clone 仓库到临时目录
  │     git clone --depth 1 --branch {branch} {repoUrl} $tempDir
  │
  ├── 4. 双向同步
  │     ├── 本地有/远程无 → 复制到远程
  │     ├── 本地无/远程有 → 复制到本地
  │     └── 都有 → 比较 updatedAt，新的覆盖旧的
  │
  ├── 5. 提交并推送 (如有变更)
  │     git add profiles/
  │     git commit -m "sync profiles at {timestamp}"
  │     git push
  │
  └── 6. 更新 lastSync 时间
```

## 时间戳比较策略

每个 profile JSON 文件需包含 `updatedAt` 字段：

```json
{
  "alias": "myapi",
  "updatedAt": "2026-03-05T10:00:00Z",
  ...
}
```

**比较规则**：
- 本地较新 → 覆盖远程
- 远程较新 → 覆盖本地
- 时间戳相同 → 跳过

## 核心函数设计

```powershell
# 主入口函数
function Sync-Profiles {
    param([string]$Mode = "sync")  # sync, push, pull
}

# 检查环境
function Test-SyncEnvironment { ... }

# 初始化/读取同步配置
function Get-SyncConfig { ... }
function Set-SyncConfig { ... }

# 执行同步
function Invoke-GitSync {
    param($Config, $Mode)
}

# 比较时间戳并合并
function Merge-Profiles {
    param($LocalProfiles, $RemoteProfiles)
}
```

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| git 未安装 | 提示安装 git |
| 认证失败 | 提示检查 SSH key 或 HTTPS credential 配置 |
| 仓库不存在 | 提示检查 URL 是否正确 |
| 网络错误 | 显示错误信息，建议检查网络后重试 |
| push 失败 | 提示可能是权限问题 |

## 用户交互示例

**首次同步**：

```
cc sync
正在初始化同步配置...

请输入 Git 仓库 URL (支持 HTTPS 或 SSH 格式): git@github.com:owner/repo.git
分支名称 [main]:
✓ 配置已保存
正在同步...
✓ 同步完成 (上传 2, 下载 1, 跳过 3)
```

**日常同步**：

```
cc sync
✓ 仓库: git@github.com:owner/repo.git
正在同步...
  ↑ 上传: new-profile.json
  ↓ 下载: team-shared.json
  = 跳过: default.json (无变化)
✓ 同步完成
```

## 需要修改的文件

- `cc.ps1`: 添加 `Sync-Profiles` 函数和 switch 分支
- `cc.ps1`: 在 `Show-Help` 中添加 sync 命令说明
- 可能需要更新 `New-Profile` 函数添加 `updatedAt` 字段
