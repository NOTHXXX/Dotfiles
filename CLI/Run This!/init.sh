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
# 0. 代理配置询问 (支持反复尝试与反悔)
# ──────────────────────────────────────────────────
section "Proxy Configuration"

while true; do
    echo -e "${YELLOW}是否需要设置临时代理来加速下载? (y/n)${NC}"
    read -r -p "> " USE_PROXY </dev/tty
    
    if [[ "$USE_PROXY" =~ ^[Nn]$ ]]; then
        info "已确认不使用代理，继续执行后续步骤。"
        break # 只有这里会彻底跳出代理配置
    elif [[ "$USE_PROXY" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}请输入代理地址 (例如 127.0.0.1:7890):${NC}"
        read -r -p "> " PROXY_ADDR
        
        if [[ -z "$PROXY_ADDR" ]]; then
            warn "地址不能为空。"
            continue # 返回循环开头，重新询问是否需要代理
        fi

        # 二次确认
        echo -e "${YELLOW}确认使用代理 http://$PROXY_ADDR 吗? (y/n)${NC}"
        read -r -p "> " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "已取消当前输入，请重新选择。"
            continue # 返回循环开头，让你有机会重新输入 y 或 n
        fi

        # 连通性验证
        info "正在验证代理 $PROXY_ADDR 的连通性..."
        if curl -s --connect-timeout 5 -I -x "http://$PROXY_ADDR" "https://www.google.com" > /dev/null; then
            info "验证成功！代理可用。"
            export http_proxy="http://$PROXY_ADDR"
            export https_proxy="http://$PROXY_ADDR"
            git config --global http.proxy "http://$PROXY_ADDR"
            git config --global https.proxy "http://$PROXY_ADDR"
            break # 验证成功，退出循环
        else
            warn "验证失败：无法连接到外部网络。"
            echo -e "${YELLOW}是要重新输入代理地址 (r)，还是直接放弃代理继续运行 (f)? (r/f)${NC}"
            read -r -p "> " FAIL_CHOICE
            if [[ "$FAIL_CHOICE" =~ ^[Ff]$ ]]; then
                info "放弃代理，尝试直接连接..."
                break
            else
                continue # 选择 r 则回到循环开头重新开始
            fi
        fi
    else
        warn "无效输入，请输入 y 或 n。"
    fi
done

# ──────────────────────────────────────────────────
# 1. 系统基础环境与 Homebrew
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

# ──────────────────────────────────────────────────
# 3. SSH 配置 (固定公钥授权)
section "SSH Configuration"

SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
MY_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6dQPskL798729mboi6wFq+pJ0/gIET7dHEhUqMtoD6 noth"

if [[ ! -d "$SSH_DIR" ]]; then
    info "创建 $SSH_DIR 目录..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

if grep -qF "$MY_PUBLIC_KEY" "$AUTH_KEYS"; then
    info "公钥已存在，无需重复添加。"
else
    echo "$MY_PUBLIC_KEY" >> "$AUTH_KEYS"
    info "公钥已成功硬编码至授权列表。"
fi

info "检查并启动 SSH 服务..."
sudo apt-get install -y openssh-server
sudo systemctl enable ssh --now

# ──────────────────────────────────────────────────
# 4. 交互式确认：运行同目录下的 install.sh
# ──────────────────────────────────────────────────
section "Next Steps"

# 根据你提供的本地路径结构，推算服务器上的对应路径
# 本地: /Users/noth/Dotfiles/CLI/Run This!/install.sh
# 服务器克隆后: $HOME/dotfiles/CLI/Run This!/install.sh
TARGET_INSTALL_SCRIPT="$DOTFILES_DIR/CLI/Run This!/install.sh"

if [[ -f "$TARGET_INSTALL_SCRIPT" ]]; then
    echo -ne "${YELLOW}仓库拉取成功。是否立即运行 $TARGET_INSTALL_SCRIPT? (y/n, 10s后默认y): ${NC}"
    read -r -t 30 response || response="y"

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "正在启动安装程序..."
        # 必须带引号，因为 "Run This!" 包含空格
        bash "$TARGET_INSTALL_SCRIPT"
    else
        info "已跳过。你可以随后手动运行: ${YELLOW}bash \"$TARGET_INSTALL_SCRIPT\"${NC}"
    fi
else
    warn "在仓库中未找到 install.sh"
    info "检查路径: $TARGET_INSTALL_SCRIPT"
fi