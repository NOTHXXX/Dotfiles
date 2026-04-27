# 📄 NOTHXXX's Dotfiles


## 🚀 一键部署与清理

初始化环境

```bash
/bin/bash -c "$(curl -x [http://192.168.31.10:20172](http://192.168.31.10:20172) -fsSL '[https://raw.githubusercontent.com/NOTHXXX/Dotfiles/main/CLI/Run%20This!/init.sh](https://raw.githubusercontent.com/NOTHXXX/Dotfiles/main/CLI/Run%20This!/init.sh)')"
```

卸载 Homebrew
```bash
/bin/bash -c "$(curl -x [http://192.168.31.10:20172](http://192.168.31.10:20172) -fsSL [https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh](https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh))"
```


##🛠️ 脚本结构说明 (Scripts Tree)
仓库中的自动化逻辑主要集中在 CLI/Run This!/ 目录下，采用分阶段解耦设计：

```
Plaintext
Dotfiles
└── CLI
    └── Run This!
        ├── init.sh          # 第一阶段：引导脚本 (Bootstrap)
        │                    # - 初始化：更新系统 apt 列表，安装基础编译工具。
        │                    # - Homebrew：自动安装并配置 Linuxbrew 环境路径。
        │                    # - 仓库管理：克隆/更新本仓库到 $HOME/dotfiles。
        │                    # - 安全：硬编码授权 SSH 公钥，确保后续 Ghostty 稳定连接。
        │                    # - 衔接：执行完毕后自动引导用户跳转至 install.sh。
        │
        ├── install.sh       # 第二阶段：软件安装脚本 (Installer)
        │                    # - 软件：读取 Brewfile 批量安装 (Yazi, Fish, FFmpeg, ImageMagick 等)。
        │                    # - Shell：将系统默认 Shell 更改为 Fish。
        │                    # - 核心：针对 Yazi 执行关键组件的强制链接 (Overwrite)。
        │                    # - 视觉：配置系统级 Nerd Fonts 字体缓存。
        │                    # - 预留：脚本末尾提供占位符，用于执行后续统一的软链接配置。
        │
        └── Brewfile         # 软件清单配置
                             # - 统一步管理所有需要安装的软件、Tap 仓库及字体。
```