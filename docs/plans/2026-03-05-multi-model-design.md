# 多模型配置设计

## 概述

允许用户在配置中保存多个模型 ID，在 `cc use` 时可以选择使用哪个模型。

## 背景

当前 cc 工具每个配置只支持单一模型 ID（通过 `model` 字段）。用户希望能够为一个供应商配置添加多个可选模型，方便在使用时快速切换。

## 目标

1. 支持在配置中保存多个模型 ID
2. `cc add/edit` 时可以手动添加多个模型
3. `cc use` 时可以选择要使用的模型
4. 向后兼容，现有配置无需修改

## 设计

### 1. 数据结构

在配置文件中新增 `models` 字段：

```json
{
  "name": "DouBaoSeed",
  "alias": "doubaoseed",
  "env": {
    "ANTHROPIC_MODEL": "glm-4.7",
    "ANTHROPIC_BASE_URL": "https://ark.cn-beijing.volces.com/api/coding",
    "ANTHROPIC_AUTH_TOKEN": "xxx"
  },
  "models": ["glm-4.7", "glm-4.8", "glm-4-plus"]
}
```

- `models` 为字符串数组，可选字段
- `env.ANTHROPIC_MODEL` 作为默认模型（向后兼容）

### 2. cc add/edit 交互

新增"可选模型"字段，用户可以：
- 依次输入模型 ID，每次回车添加一个
- 输入空行结束添加
- 支持删除已添加的模型

TUI 界面：
```
▶ 可选模型
  模型列表: [glm-4.7] [glm-4.8] [+]
```

### 3. cc use 交互

选择配置后：
- 如果配置有 `models` 数组，弹出模型选择器
- 如果没有 `models`，直接使用 `env.ANTHROPIC_MODEL`

TUI 选择器：
```
┌─ 选择模型 ─┐
│ ▶ glm-4.7  │
│   glm-4.8  │
│   glm-4-plus │
└────────────┘
↑↓ 选择 │ Enter 确认 │ Esc 取消
```

### 4. 核心模块修改

#### tui.ps1

1. 修改 `$script:FormFields`，新增"可选模型"字段
2. 新增 `Show-ModelInputForm` 函数，处理模型输入
3. 修改 `Show-ProfileSelector` 或新增 `Show-ModelSelector` 函数

#### cc.ps1

1. 修改 `New-Profile` 和 `Edit-Profile`，处理 models 数组
2. 修改 `Use-Profile`，在使用前先选择模型

## 兼容性

- 现有配置没有 `models` 字段时，不显示模型选择器
- `models` 为空数组时，也不显示模型选择器
- 读取配置时优先使用用户选择的模型，否则使用 `ANTHROPIC_MODEL`

## 错误处理

- 模型 ID 输入验证：支持任意字符串，但给出提示
- 选择模型时按 Esc，使用默认模型
