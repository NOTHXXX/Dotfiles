#!/bin/bash

# 遇到错误立即停止
set -Eeuo pipefail

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

section() { echo -e "\n${YELLOW}── $* ──${NC}"; }

# ──────────────────────────────────────────────────
# 1. 环境加载与路径定义
# ──────────────────────────────────────────────────
section "Environment Setup"

if [[ -d "/home/linuxbrew/.linuxbrew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    info "Homebrew 环境已加载"
fi

if ! command -v brew &>/dev/null; then
    die "未检测到 brew 命令，请确保已运行 init.sh。"
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$CURRENT_DIR/Brewfile"

# ──────────────────────────────────────────────────
# 2. 执行 Homebrew Bundle 安装
# ──────────────────────────────────────────────────
section "Installing Software"

# 定义代理地址
PROXY_ADDR="http://192.168.31.10:20172"

if [[ -f "$BREWFILE" ]]; then
    info "正在根据清单安装所有软件 (含 fish, yazi 等)..."
    
    # 【1. 注入环境变量代理】
    export http_proxy="$PROXY_ADDR"
    export https_proxy="$PROXY_ADDR"
    export all_proxy="$PROXY_ADDR"
    
    # 【2. 强制 Git 走代理】(关键步：brew bundle 内部会频繁调用 git)
    git config --global http.proxy "$PROXY_ADDR"
    git config --global https.proxy "$PROXY_ADDR"

    # 【3. 解决 API 响应慢】
    # 如果代理不够稳，可以尝试开启此变量强制不使用 API（虽然不推荐，但有时能避开卡死）
    # export HOMEBREW_NO_INSTALL_FROM_API=1
    
    # 执行安装
    # 加上 --verbose 可以看到具体卡在哪一步
    brew bundle --file="$BREWFILE" --verbose
    
    # 【4. 清理配置】
    git config --global --unset http.proxy
    git config --global --unset https.proxy
    unset http_proxy https_proxy all_proxy
else
    die "错误: 未能在 $CURRENT_DIR 找到 Brewfile。"
fi

# ──────────────────────────────────────────────────
# 3. 更改默认 Shell 为 Fish
# ──────────────────────────────────────────────────
section "Shell Configuration"

FISH_BIN="$(which fish)"

if [[ -n "$FISH_BIN" ]]; then
    if [[ "$SHELL" != "$FISH_BIN" ]]; then
        info "正在将默认 Shell 更改为 Fish..."
        if ! grep -qF "$FISH_BIN" /etc/shells; then
            echo "$FISH_BIN" | sudo tee -a /etc/shells
        fi
        chsh -s "$FISH_BIN"
        info "默认 Shell 更改成功。重新连接 SSH 后生效。"
    else
        info "Fish 已经是默认 Shell。"
    fi
else
    warn "未发现 Fish 安装路径，请检查 Brewfile 是否包含 fish。"
fi

# ──────────────────────────────────────────────────
# 4. Yazi 核心组件强制链接与字体配置
# ──────────────────────────────────────────────────
section "Post-Installation Tasks"

info "处理组件强制链接 (ffmpeg/imagemagick)..."
brew link --overwrite ffmpeg-full imagemagick-full || true

# 字体配置 (针对 Nerd Font 生效)
USER_FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$USER_FONT_DIR"
BREW_FONT_PATH="$(brew --prefix)/share/fonts"

if [[ -d "$BREW_FONT_PATH" ]]; then
    find "$BREW_FONT_PATH" -name "*.[o|t]tf" -exec ln -sf {} "$USER_FONT_DIR/" \;
    if command -v fc-cache &>/dev/null; then
        fc-cache -fv > /dev/null
        info "Nerd Fonts 字体库已刷新。"
    fi
fi

# ──────────────────────────────────────────────────
# 5. 验证安装结果
# ──────────────────────────────────────────────────
section "Final Verification"

for cmd in yazi fish ffmpeg fzf; do
    command -v "$cmd" &>/dev/null && echo -e "${GREEN}[OK]${NC} $cmd" || echo -e "${RED}[MISSING]${NC} $cmd"
done

if command -v npm &>/dev/null; then
    npm config set registry https://registry.npmmirror.com
    info "npm 镜像源已更新。"
fi

# ──────────────────────────────────────────────────
# 软链接与配置同步模块 - 自动识别系统调用对应配置与 flk
# ──────────────────────────────────────────────────
section "Running flk from Dotfiles"

# 1. 识别系统与架构 (仅匹配 Linux-amd64 和 macOS-M芯片)
OS=$(uname -s)
ARCH=$(uname -m)
FLK_FILENAME=""
FLK_CONFIG_NAME=""

if [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]]; then
    # 适用于 Linux x86_64 (amd64)
    FLK_FILENAME="flk-amd64"
    FLK_CONFIG_NAME="flk-amd64.json"
elif [[ "$OS" == "Darwin" && "$ARCH" == "arm64" ]]; then
    # 适用于 macOS Apple Silicon (M1/M2/M3)
    FLK_FILENAME="flk-mac"
    FLK_CONFIG_NAME="flk-mac.json"
fi

# 检查是否匹配到已知平台
if [[ -z "$FLK_FILENAME" ]]; then
    warn "当前系统架构 ($OS-$ARCH) 没有对应的预编译 flk 文件或配置。"
    warn "仅支持: Linux-x86_64 或 macOS-arm64 (M芯片)。"
    die "请检查仓库中的文件或手动编译 flk。"
fi

# 2. 链接对应的配置文件至目标位置
FLK_CONFIG_DIR="$HOME/.config/flk"
FLK_STORE_DEST="$FLK_CONFIG_DIR/flk-store.json"
FLK_STORE_SRC="$HOME/dotfiles/CLI/flk/$FLK_CONFIG_NAME"

if [[ -f "$FLK_STORE_SRC" ]]; then
    mkdir -p "$FLK_CONFIG_DIR"
    # 链接特定系统的 json 到统一的 flk-store.json
    ln -sf "$FLK_STORE_SRC" "$FLK_STORE_DEST"
    info "已将 $FLK_CONFIG_NAME 链接至 $FLK_STORE_DEST"
else
    die "错误：未在仓库中找到配置文件 $FLK_STORE_SRC"
fi

# 3. 定位并运行架构对应的 flk
FLK_EXEC="$HOME/dotfiles/$FLK_FILENAME"

if [[ -f "$FLK_EXEC" ]]; then
    info "检测到适用于 $OS-$ARCH 的执行文件: $FLK_FILENAME"
    
    chmod +x "$FLK_EXEC"
    
    # 运行 flk check
    if "$FLK_EXEC" fix; then
        info "flk fix 成功。"
        
        else
    die "错误：未找到执行文件 $FLK_EXEC。"
fi