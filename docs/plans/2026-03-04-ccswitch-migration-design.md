# cc-switch 迁移功能设计

## 概述

添加 `cc ccswitch` 命令，从旧版 cc-switch 工具的 SQLite 数据库迁移配置到本工具。

## 命令

```
cc ccswitch
```

## 数据源

- 路径: `~/.cc-switch/cc-switch.db`
- 表: `providers`
- 筛选: `app_type = 'claude'`

## 字段映射

| cc-switch 字段 | 本工具字段 | 转换规则 |
|---------------|-----------|---------|
| `name` | `alias` | 转小写，空格替换为连字符 |
| `name` | `name` | 直接使用 |
| `settings_config.env` | `env` | 直接使用 |
| - | `skipDangerousModePermissionPrompt` | 固定 `true` |

## 流程

### 1. 检测数据库

- 检查 `~/.cc-switch/cc-switch.db` 是否存在
- 不存在则提示错误并退出

### 2. 读取配置

```sql
SELECT id, name, settings_config, is_current
FROM providers
WHERE app_type = 'claude'
```

### 3. TUI 多选界面

```
▌ 从 cc-switch 导入配置
▌
▌ ▶ ○ zhipu-glm      Zhipu GLM       (当前)
▌   ○ xaio           Xaio
▌   ● yunwu          Yunwu
▌   ○ kimi-for-coding Kimi For Coding
▌
▌ ↑↓ 移动  Space 选择  Enter 确认  Esc 取消
```

- Space 切换选中状态
- Enter 确认导入选中的配置
- 显示 `(当前)` 标记原数据库的当前配置

### 4. 重复处理

- 别名不存在 → 直接写入
- 别名已存在 → 询问是否覆盖

### 5. 完成提示

```
✓ 导入完成：3 个配置
  - zhipu-glm (新)
  - yunwu (覆盖)
  - minimax (新)
```

## 实现要点

1. 使用 `sqlite3` 命令行工具查询数据库
2. 复用现有 TUI 样式（左侧竖线 + 箭头选择）
3. 需要实现多选功能（扩展现有 selector）
4. 别名生成：`$name.ToLower() -replace '\s+', '-' -replace '[^a-z0-9-]', ''`
