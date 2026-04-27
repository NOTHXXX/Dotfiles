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

if [[ -f "$BREWFILE" ]]; then
    info "正在根据清单安装所有软件 (含 fish, yazi 等)..."
    brew bundle --file="$BREWFILE"
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
# 软链接与配置同步模块 - 调用本地 flk
# ──────────────────────────────────────────────────
section "Running flk from Dotfiles"

# 1. 确认 flk-store.json 已就绪
FLK_CONFIG_DIR="$HOME/.config/flk"
FLK_STORE_DEST="$FLK_CONFIG_DIR/flk-store.json"
# 对应你提到的仓库路径
FLK_STORE_SRC="$HOME/dotfiles/CLI/flk/flk-store.json"

if [[ -f "$FLK_STORE_SRC" ]]; then
    mkdir -p "$FLK_CONFIG_DIR"
    # 使用符号链接，方便以后在仓库里直接修改配置
    ln -sf "$FLK_STORE_SRC" "$FLK_STORE_DEST"
    info "已将 flk-store.json 链接至 $FLK_STORE_DEST"
else
    die "错误：未在仓库中找到 $FLK_STORE_SRC"
fi

# 2. 定位并运行本地 flk
# 根据你提供的路径，flk 本体的可执行文件应该在 $HOME/dotfiles/flk
FLK_EXEC="$HOME/dotfiles/flk"

if [[ -f "$FLK_EXEC" ]]; then
    info "检测到本地 flk 工具，准备执行..."
    
    # 确保它有执行权限
    chmod +x "$FLK_EXEC"
    
    # 运行 flk check
    # 提示：如果 flk 是脚本（如 Python/Node），可能需要指定解释器
    # 如果它是二进制文件或已包含 Shebang，直接运行即可
    if "$FLK_EXEC" check; then
        info "flk check 预运行成功。"
        
        # 交互式询问是否执行应用（Apply）
        echo -ne "${YELLOW}是否立即应用 flk 配置以创建所有软链接? (y/n): ${NC}"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            "$FLK_EXEC" apply && info "所有软链接已成功同步！"
        fi
    else
        warn "flk check 执行失败，请检查配置文件格式。"
    fi
else
    die "错误：在 $FLK_EXEC 未找到 flk 执行文件。"
fi
