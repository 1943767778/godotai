# Godot AI Assistant

> 🤖 集成在 Godot Engine 编辑器内的 AI 游戏开发助手插件

![Godot Version](https://img.shields.io/badge/Godot-4.x-blue?logo=godotengine&logoColor=white)
![Plugin Version](https://img.shields.io/badge/Version-1.0-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## ✨ 功能特性

### 🧠 智能对话助手
- 在 Godot 编辑器侧边栏直接与 AI 对话
- 支持多轮上下文对话，自动管理历史记录
- 对话会话持久化保存，随时回溯
- 支持流式输出，实时显示 AI 回复

### 🔌 多模型支持
- **Google Gemini** - 原生集成 Gemini 模型
- **OpenAI 兼容接口** - 支持任意 OpenAI 格式的 API（包括 Ollama、本地模型等）
- 可配置多套预设，一键切换不同模型
- 自定义 Base URL，灵活对接各种 AI 服务

### 🛠️ 工具调用（Tool Calling）
AI 可直接操作你的 Godot 项目：

| 工具类别 | 能力 |
|---------|------|
| 📁 文件操作 | 创建、读取、编辑项目文件 |
| 🧩 节点操作 | 场景节点树管理、节点属性修改 |
| 📜 脚本工具 | GDScript 代码生成、检查与优化 |
| 📊 数据库工具 | 项目数据查询与分析 |
| 🧠 记忆系统 | 跨会话记忆，记住你的项目偏好 |
| 🔍 审计工具 | 代码质量检查与性能分析 |

### 📚 内置游戏开发知识库
内置 20+ 游戏开发领域专业知识：

- GDScript 现代语法与最佳实践
- 状态机、寻路 AI、动画与过场
- 物理碰撞处理、性能优化
- 关卡生成（PCG）、存档系统
- UI/UX 设计模式、音频管理
- 多人网络、本地化 i18n
- 着色器与 VFX、后处理
- 物品/任务/对话系统

### 🗂️ 项目记忆系统
- 向量数据库存储项目知识
- 自动关联相关上下文
- 跨会话记忆你的开发习惯
- 支持手动添加/删除记忆条目

## 📦 安装

### 方式一：直接下载
1. 下载本仓库的 `addons/gamedev_ai` 文件夹
2. 将其复制到你的 Godot 项目的 `addons/` 目录下
3. 打开 Godot 编辑器，进入 **项目 → 项目设置 → 插件**
4. 启用 **AI 助手** 插件

### 方式二：Git 克隆
```bash
cd your-godot-project
git clone https://github.com/1943767778/godotai.git
cp -r godotai/addons/gamedev_ai addons/
```

## 🚀 快速开始

1. **打开 AI 面板**：启用插件后，在编辑器右侧边栏找到 AI 助手图标
2. **配置 API**：
   - 点击设置按钮 ⚙️
   - 选择 Provider（Gemini / OpenAI 兼容）
   - 填入 API Key 和模型名称
   - 保存预设
3. **开始对话**：在输入框中描述你的需求，AI 会帮你完成开发任务

### 示例对话

```
你：帮我创建一个玩家移动脚本，支持 WASD 移动和跳跃
AI：好的，我来为你创建一个 CharacterBody2D 移动脚本...

你：这个角色的攻击动画在哪里？帮我加上连击系统
AI：我来查找相关文件并为你实现连击系统...
```

## 🗂️ 项目结构

```
godotai/
├── addons/
│   └── gamedev_ai/
│       ├── gamedev_ai.gd          # 插件主入口
│       ├── plugin.cfg             # 插件配置
│       ├── ai_provider.gd         # AI 提供商基类
│       ├── gemini_provider.gd     # Google Gemini 实现
│       ├── openai_provider.gd     # OpenAI 兼容实现
│       ├── context_manager.gd     # 上下文管理
│       ├── tool_executor.gd       # 工具调用执行器
│       ├── memory_manager.gd      # 记忆系统管理
│       ├── vector_db.gd           # 向量数据库
│       ├── system_prompt.gd       # 系统提示词
│       ├── logger.gd              # 日志系统
│       ├── locale_manager.gd       # 多语言管理
│       ├── git_manager.gd         # Git 集成
│       ├── dock/                  # 面板 UI
│       ├── skills/                # 内置技能知识库
│       ├── tools/                 # 工具调用实现
│       └── assets/                # 图标与资源
├── project.godot                  # Godot 项目配置
└── README.md                       # 本文件
```

## 🛠️ 支持的 Provider

| Provider | 说明 |
|----------|------|
| **Gemini** | Google Gemini 系列模型（需 API Key） |
| **OpenAI 兼容** | OpenAI API、Ollama、vLLM、OneAPI 等任意兼容服务 |

## ⚙️ 配置说明

在插件设置中可以配置：

- **Provider 类型**：选择 AI 服务提供商
- **API Key**：你的 API 密钥
- **Base URL**：API 接口地址（默认官方地址）
- **模型名称**：如 `gemini-2.0-flash`、`gpt-4o`、`llama3` 等
- **自定义指令**：全局系统提示词定制
- **截图功能**：是否允许 AI 获取编辑器截图
- **回复语言**：指定 AI 回复的语言

## 📋 系统要求

- **Godot Engine** 4.0 或更高版本（推荐 4.2+）
- 网络连接（使用云端 API 时）
- 有效的 AI 服务 API Key

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

---

<div align="center">
  <b>由 ❤️ 构建，服务于 Godot 游戏开发者社区</b>
</div>
