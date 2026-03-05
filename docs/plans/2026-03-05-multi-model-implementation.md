# 多模型配置实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 允许用户在配置中保存多个模型 ID，在 cc use 时可以选择使用哪个模型

**Architecture:** 在配置中新增 models 数组字段，修改 tui.ps1 的表单和选择器，修改 cc.ps1 的创建和使用逻辑

**Tech Stack:** PowerShell 7.0, TUI 界面

---

### Task 1: 修改 tui.ps1 - 新增可选模型字段

**Files:**
- Modify: `tui.ps1:317-330` (FormFields 定义)

**Step 1: 修改 FormFields 定义**

在 `tui.ps1` 第 317-330 行，将现有字段修改为：

```powershell
$script:FormFields = @(
    @{ Key = 'alias'; Label = '别名'; Required = $true }
    @{ Key = 'name'; Label = '显示名称'; Required = $true }
    @{ Key = 'baseUrl'; Label = 'API 地址'; Required = $true }
    @{ Key = 'token'; Label = '认证令牌'; Required = $true; Masked = $true }
    @{ Key = 'model'; Label = '默认模型'; Required = $true }
    @{ Key = 'models'; Label = '可选模型'; Required = $false; IsArray = $true }
    @{ Key = 'sonnetModel'; Label = 'Sonnet'; Required = $false }
    @{ Key = 'opusModel'; Label = 'Opus'; Required = $false }
    @{ Key = 'haikuModel'; Label = 'Haiku'; Required = $false }
    @{ Key = 'reasoningModel'; Label = '推理模型'; Required = $false }
)
```

**Step 2: 提交**

```bash
git add tui.ps1
git commit -m "feat(models): 在 FormFields 中新增可选模型字段"
```

---

### Task 2: 修改 tui.ps1 - 处理 models 字段读取

**Files:**
- Modify: `tui.ps1:413-430` (Show-ConfigForm 初始化逻辑)

**Step 1: 修改初始化逻辑**

在 `Show-ConfigForm` 函数中，读取现有配置的 models 字段：

```powershell
# 在现有的 foreach ($field in $script:FormFields) 循环中，添加：
'models' {
    $models = @()
    if ($ExistingConfig.env.PSObject.Properties.Name -contains 'ANTHROPIC_MODELS') {
        $models = $ExistingConfig.env.ANTHROPIC_MODELS | ConvertFrom-Json
    }
    $values[$key] = $models
}
```

**Step 2: 提交**

```bash
git add tui.ps1
git commit -m "feat(models): 处理 models 字段的读取"
```

---

### Task 3: 新增 tui.ps1 - Show-ModelInputForm 函数

**Files:**
- Create: `tui.ps1` 末尾新增函数

**Step 1: 添加模型输入表单函数**

在 `tui.ps1` 末尾添加：

```powershell
# 显示模型输入表单
function Show-ModelInputForm {
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$ExistingModels = @()
    )

    $a = $script:ANSI
    $models = @() + $ExistingModels

    while ($true) {
        Clear-Screen
        Write-Host ""
        Write-LeftBarLine "$($a.Cyan)添加可选模型$($a.Reset)"
        Write-LeftBarLine ""

        # 显示已添加的模型
        if ($models.Count -gt 0) {
            Write-LeftBarLine "已添加的模型："
            for ($i = 0; $i -lt $models.Count; $i++) {
                Write-LeftBarLine "  $($i + 1). $($models[$i])"
            }
            Write-LeftBarLine ""
        }

        Write-LeftBarLine "输入模型 ID（回车添加，空行结束）："
        Write-LeftBarLine ""

        # 显示输入框
        $inputBox = "[                              ]"
        Write-LeftBarLine "  $inputBox"

        Write-LeftBarLine ""
        Write-LeftBarLine "$($a.BrightBlack)↑↓ 上下移动 │ 回车 添加 │ Delete 删除 │ Esc 完成$($a.Reset)"

        # 读取输入
        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input)) {
            break
        }
        $models += $input.Trim()
    }

    return $models
}
```

**Step 2: 提交**

```bash
git add tui.ps1
git commit -t "feat(models): 新增 Show-ModelInputForm 函数"
```

---

### Task 4: 修改 tui.ps1 - 表单处理 models 输入

**Files:**
- Modify: `tui.ps1:500-580` (Show-ConfigForm 主循环)

**Step 1: 修改主循环处理 models 字段**

在表单主循环中，当焦点在 models 字段时，按回车调用 `Show-ModelInputForm`：

```powershell
# 在按键处理部分，添加：
'models' {
    if ($key -eq 'Enter' -or $isCurrentField) {
        $models = Show-ModelInputForm -ExistingModels $values['models']
        $values['models'] = $models
    }
}
```

**Step 2: 提交**

```bash
git add tui.ps1
git commit -m "feat(models): 表单支持添加多个模型"
```

---

### Task 5: 修改 tui.ps1 - 显示模型列表

**Files:**
- Modify: `tui.ps1:450-480` (表单显示逻辑)

**Step 1: 修改显示逻辑**

在 models 字段显示时，显示已添加的模型列表：

```powershell
# 在字段显示部分，修改 models 字段显示：
if ($field.Key -eq 'models') {
    $modelCount = if ($values['models']) { $values['models'].Count } else { 0 }
    $displayValue = "($modelCount 个模型)"
}
```

**Step 2: 提交**

```bash
git add tui.ps1
git commit -m "feat(models): 表单显示模型数量"
```

---

### Task 6: 新增 tui.ps1 - Show-ModelSelector 函数

**Files:**
- Create: `tui.ps1` 末尾新增函数

**Step 1: 添加模型选择器函数**

在 `tui.ps1` 末尾添加：

```powershell
# 显示模型选择器
function Show-ModelSelector {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Models,

        [Parameter(Mandatory=$false)]
        [string]$Title = "选择模型"
    )

    $width = 30
    $a = $script:ANSI
    $selectedIndex = 0

    Hide-Cursor

    while ($true) {
        Clear-Screen

        $b = $script:Border
        Write-Host ""
        Write-Host " $b$($a.Cyan)$Title$a.Reset$b " -NoNewline
        Write-Host ""
        Write-Host ""

        # 显示模型列表
        for ($i = 0; $i -lt $Models.Count; $i++) {
            $model = $Models[$i]
            if ($i -eq $selectedIndex) {
                Write-Host "$($a.Cyan)▶ $($model)$($a.Reset)"
            } else {
                Write-Host "  $model"
            }
        }

        Write-Host ""
        Write-Host "$($a.BrightBlack)↑↓ 选择 │ Enter 确认 │ Esc 取消$($a.Reset)"

        $key = Read-Key

        switch ($key) {
            'ArrowUp' {
                $selectedIndex = [Math]::Max(0, $selectedIndex - 1)
            }
            'ArrowDown' {
                $selectedIndex = [Math]::Min($Models.Count - 1, $selectedIndex + 1)
            }
            'Enter' {
                Show-Cursor
                return $Models[$selectedIndex]
            }
            'Escape' {
                Show-Cursor
                return $null
            }
        }
    }
}
```

**Step 2: 提交**

```bash
git add tui.ps1
git commit -m "feat(models): 新增 Show-ModelSelector 函数"
```

---

### Task 7: 修改 cc.ps1 - New-Profile 保存 models

**Files:**
- Modify: `cc.ps1:506-530` (New-Profile 函数)

**Step 1: 修改 New-Profile 保存逻辑**

在 `New-Profile` 函数中，处理 models 数组保存：

```powershell
# 在保存配置文件部分，修改为：
if ($result) {
    # 处理 models 数组
    $envVars = @{}
    foreach ($key in $result.env.Keys) {
        $envVars[$key] = $result.env[$key]
    }
    if ($result.models -and $result.models.Count -gt 0) {
        $envVars['ANTHROPIC_MODELS'] = ($result.models | ConvertTo-Json)
    }

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
```

**Step 2: 提交**

```bash
git add cc.ps1
git commit -m "feat(models): New-Profile 保存 models 到配置"
```

---

### Task 8: 修改 cc.ps1 - Edit-Profile 处理 models

**Files:**
- Modify: `cc.ps1:586-620` (Edit-Profile 函数)

**Step 1: 修改 Edit-Profile 函数**

参考 New-Profile 修改 Edit-Profile 函数，确保保存时处理 models 数组。

**Step 2: 提交**

```bash
git add cc.ps1
git commit -m "feat(models): Edit-Profile 处理 models 更新"
```

---

### Task 9: 修改 cc.ps1 - Use-Profile 添加模型选择

**Files:**
- Modify: `cc.ps1:540-580` (Use-Profile 函数)

**Step 1: 修改 Use-Profile 函数**

在选择配置后、启动 Claude Code 前，添加模型选择逻辑：

```powershell
# 在读取配置后，生成临时配置文件前：
$selectedModel = $config.env.ANTHROPIC_MODEL  # 默认模型

# 如果有多个模型，弹出选择器
if ($config.env.PSObject.Properties.Name -contains 'ANTHROPIC_MODELS') {
    $modelsJson = $config.env.ANTHROPIC_MODELS
    if ($modelsJson) {
        $models = $modelsJson | ConvertFrom-Json
        if ($models -is [String]) {
            $models = @($models)
        }
        if ($models.Count -gt 0) {
            $selectedModel = Show-ModelSelector -Models $models
            if (-not $selectedModel) {
                $selectedModel = $config.env.ANTHROPIC_MODEL
            }
        }
    }
}

# 使用选定的模型
$config.env.ANTHROPIC_MODEL = $selectedModel
```

**Step 2: 提交**

```bash
git add cc.ps1
git commit -m "feat(models): Use-Profile 添加模型选择器"
```

---

### Task 10: 测试完整流程

**Step 1: 测试创建配置**

```powershell
# 运行 cc new 添加新配置，测试模型输入功能
cc new
```

**Step 2: 测试模型选择**

```powershell
# 运行 cc use 选择配置，测试模型选择器
cc use [alias]
```

**Step 3: 提交**

```bash
git add .
git commit -m "test: 手动测试多模型功能"
```

---

## 执行选项

**Plan complete and saved to `docs/plans/2026-03-05-multi-model-implementation.md`. Two execution options:**

1. **Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

2. **Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
