# Claude Code 配置管理工具设计

## 概述

一个轻量级 PowerShell CLI 工具，用于管理 Claude Code 的第三方供应商配置，支持快速切换和启动。

## 实现决策

> 以下决策基于 2026-03-04 的讨论确定

| 决策项 | 选择 | 说明 |
|--------|------|------|
| 界面风格 | 完整 TUI | 基于 PowerShell 7，使用 ANSI 转义序列 |
| 启动机制 | 临时配置文件 | 生成临时 settings.json，try/finally 确保清理 |
| 配置格式 | 完整字段 | 按设计文档保留所有模型映射字段 |
| 实现顺序 | TUI 框架优先 | 先搭建 TUI 组件，再补充命令逻辑 |
| 存放位置 | 当前项目目录 | 便于版本管理 |
| 测试端点 | 简单 messages 请求 | 发送简单请求验证连接和认证 |
| 备份功能 | 不需要 | 保持简单 |

## 技术方案

- **技术栈**: PowerShell 7+ (TUI 界面，无外部依赖)
- **存储位置**: `~/.cc/`（配置文件），脚本存放于项目目录
- **配置格式**: 与 Claude Code `settings.json` 一致

## 目录结构

```
~/.cc/
├── profiles/           # 配置文件目录
│   ├── glm.json
│   ├── deepseek.json
│   └── openrouter.json
├── current             # 当前使用的别名（纯文本）

cc-helper/              # 脚本目录（项目仓库）
├── cc.ps1              # 主脚本入口
└── tui.ps1             # TUI 模块（选择器、表单）
```

## 配置文件格式

```json
{
  "name": "智谱 GLM",
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "xxx",
    "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
    "ANTHROPIC_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5",
    "ANTHROPIC_REASONING_MODEL": "glm-5"
  },
  "skipDangerousModePermissionPrompt": true
}
```

### 字段说明

| 字段 | 可编辑 | 说明 |
|------|:------:|------|
| `name` | ✓ | 显示名称 |
| `env.ANTHROPIC_AUTH_TOKEN` | ✓ | 认证令牌 |
| `env.ANTHROPIC_BASE_URL` | ✓ | API 地址 |
| `env.ANTHROPIC_MODEL` | ✓ | 默认模型 |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | ✓ | Sonnet 模型映射 |
| `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | ✓ | Opus 模型映射 |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | ✓ | Haiku 模型映射 |
| `env.ANTHROPIC_REASONING_MODEL` | ✓ | 推理模型映射 |
| `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | ✗ | 固定 `"1"` |
| `skipDangerousModePermissionPrompt` | ✗ | 固定 `true` |

### 别名规则

- 别名 = 配置文件名（不含 `.json` 扩展名）
- 示例: `glm.json` → 别名 `glm`
- 使用时: `./cc.ps1 use glm`

## 命令行接口

```powershell
# 无参数：显示帮助和当前配置信息
./cc.ps1

# 切换配置并启动 Claude Code
./cc.ps1 use [alias]    # 无参数时显示 TUI 选择器

# 列出所有配置
./cc.ps1 list

# 新建配置（交互式 TUI 表单）
./cc.ps1 new

# 编辑配置
./cc.ps1 edit [alias]   # 无参数时显示 TUI 选择器

# 删除配置
./cc.ps1 rm [alias]     # 无参数时显示 TUI 选择器

# 测试 API 连接
./cc.ps1 test [alias]   # 无参数时显示 TUI 选择器
```

### 命令处理流程

#### `use [alias]`

```
┌─ 有参数 ────────────────────────────────┐
│ 1. 验证配置存在                          │
│ 2. 切换配置，启动 Claude Code            │
└─────────────────────────────────────────┘

┌─ 无参数 ────────────────────────────────┐
│ 1. 加载配置列表                          │
│ 2. 空列表 → 提示 "暂无配置，使用 cc new 创建" │
│ 3. 调用 Show-ProfileSelector            │
│ 4. 返回 null → 退出                     │
│ 5. 返回 alias → 切换配置，启动 Claude Code │
└─────────────────────────────────────────┘
```

#### `edit [alias]`

```
┌─ 有参数 ────────────────────────────────┐
│ 1. 验证配置存在                          │
│ 2. 调用 Show-ConfigForm -IsEdit         │
│ 3. 保存配置                             │
└─────────────────────────────────────────┘

┌─ 无参数 ────────────────────────────────┐
│ 1. 加载配置列表                          │
│ 2. 空列表 → 提示退出                     │
│ 3. 调用 Show-ProfileSelector            │
│ 4. 返回 alias → 调用 Show-ConfigForm    │
│ 5. 保存配置                             │
└─────────────────────────────────────────┘
```

#### `rm [alias]`

```
┌─ 有参数 ────────────────────────────────┐
│ 1. 验证配置存在                          │
│ 2. 确认删除 (Y/n)                       │
│ 3. 删除配置文件                         │
└─────────────────────────────────────────┘

┌─ 无参数 ────────────────────────────────┐
│ 1. 加载配置列表                          │
│ 2. 空列表 → 提示退出                     │
│ 3. 调用 Show-ProfileSelector            │
│ 4. 返回 alias → 确认删除 (Y/n)          │
│ 5. 删除配置文件                         │
└─────────────────────────────────────────┘
```

#### `test [alias]`

```
┌─ 有参数 ────────────────────────────────┐
│ 1. 验证配置存在                          │
│ 2. 执行 API 测试                        │
│ 3. 显示结果                             │
└─────────────────────────────────────────┘

┌─ 无参数 ────────────────────────────────┐
│ 1. 加载配置列表                          │
│ 2. 空列表 → 提示退出                     │
│ 3. 调用 Show-ProfileSelector            │
│ 4. 返回 alias → 执行 API 测试           │
│ 5. 显示结果                             │
└─────────────────────────────────────────┘
```

### 无参数输出示例

```
Claude Code 配置管理工具

当前配置: glm (智谱 GLM)
Base URL: https://open.bigmodel.cn/api/anthropic
模型: glm-5

命令:
  cc use [alias]  切换配置并启动 Claude Code (无参数显示选择器)
  cc list         列出所有配置
  cc new          创建新配置
  cc edit [alias] 编辑配置 (无参数显示选择器)
  cc rm [alias]   删除配置 (无参数显示选择器)
  cc test [alias] 测试 API 连接 (无参数显示选择器)
```

## 核心功能

### 1. CLI 命令

| 命令 | 功能 | 无参数行为 |
|------|------|------------|
| (无参数) | 显示帮助和当前配置 | - |
| use | 切换配置并启动 Claude Code | TUI 选择器 |
| list | 列出所有配置 | - |
| new | 创建新配置 | TUI 表单 |
| edit | 编辑配置 | TUI 选择器 → TUI 表单 |
| rm | 删除配置 | TUI 选择器 |
| test | 测试 API 连接 | TUI 选择器 |

## TUI 模块设计 (tui.ps1)

### 模块 API

#### `Show-ProfileSelector`

显示配置选择列表，返回选中的配置别名。

```powershell
function Show-ProfileSelector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$Profiles,      # 配置列表 @{alias; name; isCurrent}

        [Parameter(Mandatory=$false)]
        [string]$Title = "选择配置"   # 标题文字
    )

    # 返回值：
    # - 选中配置的别名 (string)
    # - $null 表示用户取消 (Esc)
}
```

#### `Show-ConfigForm`

显示新建/编辑配置表单，返回配置对象。

```powershell
function Show-ConfigForm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$ExistingConfig,  # 编辑模式：现有配置

        [Parameter(Mandatory=$false)]
        [switch]$IsEdit              # 是否为编辑模式
    )

    # 返回值：
    # - 配置对象 @{alias; name; env: @{...}}
    # - $null 表示用户取消 (Esc)
}
```

### 空状态处理

当 `$Profiles` 为空数组时：
- 显示居中提示：`暂无配置，使用 cc new 创建`
- 底部显示：`按任意键退出`
- 返回 `$null`

### 视觉样式

| 元素 | ANSI 样式 |
|------|-----------|
| 边框 | `\e[36m` (青色) |
| 标题 | `\e[1;37m` (粗体白色) |
| 当前选项 | `\e[7m` (反色高亮) |
| 当前配置标记 | `\e[32m●\e[0m` (绿色圆点) |
| 帮助文字 | `\e[90m` (灰色) |

## TUI 界面设计

### 1. 供应商选择列表 (use/rm/edit/test 无参数时)

```
╔══════════════════════════════════════════════════════════════╗
║                    ✦ 选择配置                                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║   ┌──────────────────────────────────────────────────────┐   ║
║   │  ● glm        智谱 GLM                               │   ║
║   ├──────────────────────────────────────────────────────┤   ║
║   │    deepseek   DeepSeek AI                            │   ║
║   ├──────────────────────────────────────────────────────┤   ║
║   │    openrouter OpenRouter                             │   ║
║   └──────────────────────────────────────────────────────┘   ║
║                                                              ║
║   ● 当前使用的配置                                            ║
║                                                              ║
║   ↑↓ 选择 │ Enter 确认 │ Esc 取消                            ║
╚══════════════════════════════════════════════════════════════╝
```

### 2. 新建/编辑配置表单

```
╔══════════════════════════════════════════════════════════════╗
║                    ✦ 新建配置                                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║   别名        [________________________]                     ║
║   显示名称    [________________________]                     ║
║   API 地址    [________________________]                     ║
║   认证令牌    [________________________]  ○ 隐藏            ║
║                                                              ║
║   ── 模型配置 (留空使用默认值) ──                            ║
║                                                              ║
║   默认模型    [________________________]  *必填              ║
║   Sonnet      [________________________]                     ║
║   Opus        [________________________]                     ║
║   Haiku       [________________________]                     ║
║   推理模型    [________________________]                     ║
║                                                              ║
║   ↑↓切换 │ Tab下一项 │ Space显隐令牌 │ Ctrl+S保存 │ Esc取消 ║
╚══════════════════════════════════════════════════════════════╝
```

### 键盘导航

| 按键 | 功能 |
|------|------|
| `↑` `↓` | 上下选择 |
| `Tab` | 切换字段 |
| `Enter` | 确认选择 (列表) |
| `Ctrl+S` | 保存配置 (表单) |
| `Esc` | 取消退出 |
| `Space` | 切换令牌显示/隐藏 |

### 交互逻辑

**供应商选择列表:**
- `use`: 选择后切换配置并启动 Claude Code
- `edit`: 选择后进入编辑表单
- `rm`: 选择后确认删除
- `test`: 选择后测试 API 连接

**配置表单:**
- **令牌字段**: 默认隐藏，点击右侧 `○ 隐藏` 或按 Space 切换
- **模型字段**: 留空时自动使用"默认模型"的值
- **必填验证**: 保存时检查必填字段，未填写高亮提示
- **编辑模式**: 预填充现有配置值，别名不可修改

### 视觉反馈

- 当前选项: 高亮背景显示
- 当前字段: 高亮边框显示
- 错误提示: 红色文字显示在字段下方

### 表单字段定义

| 字段 | 键名 | 必填 | 默认值 | 验证规则 |
|------|------|:----:|--------|----------|
| 别名 | `alias` | ✓ | - | 仅小写字母/数字/连字符，不可重复，编辑时不可修改 |
| 显示名称 | `name` | ✓ | - | 非空 |
| API 地址 | `env.ANTHROPIC_BASE_URL` | ✓ | - | 有效的 URL 格式 |
| 认证令牌 | `env.ANTHROPIC_AUTH_TOKEN` | ✓ | - | 非空 |
| 默认模型 | `env.ANTHROPIC_MODEL` | ✓ | - | 非空 |
| Sonnet | `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | ✗ | 使用默认模型 | - |
| Opus | `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | ✗ | 使用默认模型 | - |
| Haiku | `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | ✗ | 使用默认模型 | - |
| 推理模型 | `env.ANTHROPIC_REASONING_MODEL` | ✗ | 使用默认模型 | - |

### 字段验证规则

```powershell
# 验证函数示例
function Test-Alias {
    param([string]$alias, [string[]]$existingAliases, [bool]$isEdit)
    if ([string]::IsNullOrWhiteSpace($alias)) {
        return "别名不能为空"
    }
    if ($alias -notmatch '^[a-z0-9-]+$') {
        return "别名只能包含小写字母、数字和连字符"
    }
    if (-not $isEdit -and $alias -in $existingAliases) {
        return "别名已存在"
    }
    return $null  # 验证通过
}

function Test-Url {
    param([string]$url)
    if ([string]::IsNullOrWhiteSpace($url)) {
        return "API 地址不能为空"
    }
    if ($url -notmatch '^https?://') {
        return "API 地址必须以 http:// 或 https:// 开头"
    }
    return $null
}
```

### 验证错误显示

```
╔══════════════════════════════════════════════════════════════╗
║                    ✦ 新建配置                                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║   别名        [glm-___________________]                      ║
║               └─ ✗ 别名已存在                                 ║  ← 红色
║                                                              ║
║   显示名称    [智谱 GLM______________]                       ║
║   API 地址    [________________________]                      ║
║               └─ ✗ API 地址不能为空                          ║  ← 红色
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

### 删除确认对话框

```
╔══════════════════════════════════════════════════════════════╗
║                    ✦ 确认删除                                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║   确定要删除配置 "deepseek" 吗？                              ║
║                                                              ║
║   ┌────────────┐   ┌────────────┐                            ║
║   │    删除    │   │    取消    │                            ║
║   └────────────┘   └────────────┘                            ║
║      ← Tab 切换 →                                            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

**交互:**
- `Tab` / `←` `→` 切换按钮
- `Enter` 确认当前按钮
- `Esc` 取消（等同于点击取消按钮）
- 默认焦点在"取消"按钮上（安全设计）

### 2. API 连接测试

1. 读取 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`
2. 发送请求到 `/v1/models` 端点
3. 显示连接状态和响应时间

### 3. 启动 Claude Code

生成临时 settings.json 并执行：

```powershell
claude --settings $tempSettingsPath
```

启动前自动注入固定字段：
- `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"`

## 实现要点

### 1. 配置文件操作

```powershell
# 读取所有配置
Get-ChildItem ~/.cc/profiles/*.json | ForEach-Object {
    $config = Get-Content $_.FullName | ConvertFrom-Json
    $config | Add-Member -NotePropertyName "alias" -NotePropertyValue $_.BaseName
}

# 获取当前配置
$currentAlias = Get-Content ~/.cc/current -ErrorAction SilentlyContinue
```

### 2. 生成启动配置

```powershell
# 读取配置
$config = Get-Content ~/.cc/profiles/$alias.json | ConvertFrom-Json

# 注入固定字段
$config.env | Add-Member -NotePropertyName "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" -NotePropertyValue "1" -Force

# 生成临时文件
$tempPath = [System.IO.Path]::GetTempFileName()
$config | ConvertTo-Json -Depth 10 | Set-Content $tempPath

# 启动
claude --settings $tempPath
```

### 3. TUI 核心实现

#### ANSI 转义序列常量

```powershell
# 光标控制
$ANSI = @{
    # 光标移动
    CursorUp       = "`e[A"
    CursorDown     = "`e[B"
    CursorRight    = "`e[C"
    CursorLeft     = "`e[D"
    CursorHome     = "`e[H"
    CursorPos      = "`e[{0};{1}H"  # -f row, col

    # 清除
    ClearScreen    = "`e[2J"
    ClearLine      = "`e[2K"
    ClearToEnd     = "`e[0K"

    # 颜色
    Reset          = "`e[0m"
    Bold           = "`e[1m"
    Dim            = "`e[2m"
    Reverse        = "`e[7m"        # 反色（高亮背景）

    # 前景色
    Black          = "`e[30m"
    Red            = "`e[31m"
    Green          = "`e[32m"
    Yellow         = "`e[33m"
    Blue           = "`e[34m"
    Magenta        = "`e[35m"
    Cyan           = "`e[36m"
    White          = "`e[37m"
    BrightBlack    = "`e[90m"       # 灰色
    BrightRed      = "`e[91m"
    BrightGreen    = "`e[92m"

    # 背景色
    BgBlack        = "`e[40m"
    BgBlue         = "`e[44m"
    BgCyan         = "`e[46m"
    BgWhite        = "`e[47m"
}
```

#### 键盘输入处理

```powershell
function Read-Key {
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    return @{
        Key       = $key.KeyCode      # Keys 枚举
        Character = $key.Character    # 字符
        Modifiers = $key.ControlKeyState
    }
}

function Test-CtrlKey {
    param($key)
    return $key.Modifiers -band [ConsoleModifiers]::Control
}

# 方向键检测
switch ($key.Key) {
    'UpArrow'   { $selectedIndex-- }
    'DownArrow' { $selectedIndex++ }
    'Enter'     { return $profiles[$selectedIndex] }
    'Escape'    { return $null }
}
```

#### 绘制选择列表

```powershell
function Draw-Selector {
    param(
        [hashtable[]]$Items,
        [int]$SelectedIndex,
        [int]$Top,
        [int]$Left
    )

    for ($i = 0; $i -lt $Items.Count; $i++) {
        # 移动光标到行首
        Write-Host "$($ANSI.CursorPos -f ($Top + $i), $Left)" -NoNewline

        $item = $Items[$i]
        $isSelected = ($i -eq $SelectedIndex)
        $isCurrent = $item.isCurrent

        # 高亮当前选中项
        if ($isSelected) {
            Write-Host $ANSI.Reverse -NoNewline
        }

        # 当前配置标记
        $marker = if ($isCurrent) { "$($ANSI.Green)●$($ANSI.Reset)" } else { " " }

        # 绘制行内容
        Write-Host "  $marker $($item.alias.PadRight(12)) $($item.name)" -NoNewline

        if ($isSelected) {
            Write-Host $ANSI.Reset -NoNewline
        }
    }
}
```

### 4. 错误处理

| 错误场景 | 处理方式 |
|----------|----------|
| 配置文件损坏 | 显示错误信息，跳过该配置 |
| 配置目录不存在 | 自动创建 `~/.cc/profiles/` |
| 别名不存在 | 显示 "配置 '{alias}' 不存在" |
| 令牌为空 | 表单验证拦截 |
| API 连接失败 | 显示错误信息和状态码 |
| 网络超时 | 显示 "连接超时，请检查网络" |
| 用户取消操作 | 静默退出，不显示错误 |

```powershell
# 错误显示函数
function Show-Error {
    param([string]$Message)
    Write-Host "`n$($ANSI.BrightRed)✗ $Message$($ANSI.Reset)`n"
}

# 配置加载容错
function Get-Profiles {
    $profiles = @()
    foreach ($file in Get-ChildItem ~/.cc/profiles/*.json -ErrorAction SilentlyContinue) {
        try {
            $config = Get-Content $file.FullName | ConvertFrom-Json
            $profiles += @{
                alias     = $file.BaseName
                name      = $config.name
                isCurrent = ($file.BaseName -eq $currentAlias)
            }
        }
        catch {
            Write-Warning "配置文件损坏: $($file.Name)"
        }
    }
    return $profiles
}
```

## 依赖

- PowerShell 7+（支持 ANSI 转义序列 `` `e ``）
- Claude Code CLI（已安装）

## 其他命令设计

### list 命令输出格式

```
配置列表 (3 个)

  别名          显示名称              模型
  ────────────────────────────────────────────
● glm          智谱 GLM              glm-5
  deepseek     DeepSeek AI           deepseek-chat
  openrouter   OpenRouter            claude-3-opus

● 当前使用的配置
```

### API 测试实现

```powershell
function Test-ApiConnection {
    param(
        [string]$BaseUrl,
        [string]$Token
    )

    $startTime = Get-Date

    try {
        # 使用简单的 messages 请求测试连接
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
            Message = "连接成功"
        }
    }
    catch {
        $errorMsg = switch ($_.Exception.Response.StatusCode) {
            401 { "认证失败，请检查令牌" }
            403 { "访问被拒绝" }
            404 { "API 端点不存在" }
            500 { "服务器内部错误" }
            default { "连接失败: $($_.Exception.Message)" }
        }

        return @{
            Success = $false
            Message = $errorMsg
        }
    }
}
```

### 测试结果显示

```
测试配置: glm (智谱 GLM)

  API 地址: https://open.bigmodel.cn/api/anthropic
  模型: glm-5

  ┌────────────────────────────────────────┐
  │  ✓ 连接成功                            │  ← 绿色
  │    响应时间: 234ms                      │
  └────────────────────────────────────────┘
```

```
测试配置: deepseek (DeepSeek AI)

  API 地址: https://api.deepseek.com
  模型: deepseek-chat

  ┌────────────────────────────────────────┐
  │  ✗ 连接失败                            │  ← 红色
  │    认证失败，请检查令牌                 │
  └────────────────────────────────────────┘
```

## 文件清单

```
cc-helper/
├── cc.ps1              # 主脚本（命令解析、业务逻辑）
├── tui.ps1             # TUI 模块（选择器、表单）
└── docs/
    └── plans/
        └── 2026-03-04-cc-config-manager-design.md  # 本文档
```
