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
# 1. 系统基础环境与 Homebrew
# ──────────────────────────────────────────────────
section "System & Homebrew"

info "更新系统软件包列表..."
sudo apt-get update -y && sudo apt-get install -y build-essential curl git procps file

if command -v brew &>/dev/null; then
    info "Homebrew 已安装，跳过"
else
    info "正在安装 Homebrew (Linuxbrew)..."
    /bin/bash -c "$(curl -fsSL https://kkgithub.com/Homebrew/install/raw/HEAD/install.sh)"
    
    if [[ -d "/home/linuxbrew/.linuxbrew" ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.bashrc"
    fi
fi

# ──────────────────────────────────────────────────
# 2. 拉取 Dotfiles 仓库
# ──────────────────────────────────────────────────
section "Dotfiles Repository"

DOTFILES_DIR="$HOME/dotfiles"
REPO_URL="https://kkgithub.com/NOTHXXX/Dotfiles.git"
MAX_RETRY=3

if [[ -d "$DOTFILES_DIR" ]]; then
    info "目录 $DOTFILES_DIR 已存在，尝试执行 git pull..."
    cd "$DOTFILES_DIR" && git pull
else
    info "正在克隆仓库..."
    for i in $(seq 1 $MAX_RETRY); do
        git clone "$REPO_URL" "$DOTFILES_DIR" && break
        warn "第 $i 次克隆失败，5秒后重试..."
        sleep 5
        if [[ $i -eq $MAX_RETRY ]]; then
            die "克隆失败，请检查网络连接。"
        fi
    done
fi

info "所有基础步骤已完成！"
echo -e "你的仓库已准备就绪：${GREEN}$DOTFILES_DIR${NC}"
echo -e "你可以接着运行: ${YELLOW}bash $DOTFILES_DIR/scripts/restore.sh${NC}"