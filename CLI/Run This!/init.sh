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
# 1. 系统基础环境与 Homebrew (镜像加速版)
# ──────────────────────────────────────────────────
section "System & Homebrew"

info "更新系统软件包列表..."
sudo apt-get update -y && sudo apt-get install -y build-essential curl git procps file

# ... 前面代码保持不变 ...

if command -v brew &>/dev/null; then
    info "Homebrew 已安装，跳过"
else
    info "正在通过镜像安装 Homebrew (Linuxbrew)..."
    
    # 临时镜像环境变量
    export HOMEBREW_INSTALL_FROM_API=1
    export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
    export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
    export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
    
    /bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/functions/install/homebrew-install.sh)"
    
    # 【核心修改 1】: 确定安装路径并立即注入当前 Shell 会话
    BREW_PATH="/home/linuxbrew/.linuxbrew/bin/brew"
    if [[ -f "$BREW_PATH" ]]; then
        # 这一步非常重要！让当前运行中的 init.sh 进程立刻认识 brew
        eval "$($BREW_PATH shellenv)"
        
        # 写入 .bashrc 供以后登录使用
        {
          echo "eval \"\$($BREW_PATH shellenv)\""
          echo 'export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"'
          echo 'export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"'
          echo 'export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"'
        } >> "$HOME/.bashrc"
        
        info "Homebrew 环境变量已即时加载并写入 .bashrc"
    else
        die "Homebrew 安装似乎失败，找不到 $BREW_PATH"
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

TARGET_INSTALL_SCRIPT="$DOTFILES_DIR/CLI/Run This!/install.sh"

if [[ -f "$TARGET_INSTALL_SCRIPT" ]]; then
    # 解决 curl | bash 模式下 read 无法读取用户输入的问题
    # 将标准输入重定向回终端 (/dev/tty)
    echo -ne "${YELLOW}仓库拉取成功。是否立即运行安装脚本? (y/n, 30s后默认y): ${NC}"
    if [[ -t 0 ]]; then
        read -r -t 30 response || response="y"
    else
        # 如果是在管道中运行，尝试从控制台获取输入
        read -r -t 30 response < /dev/tty || response="y"
    fi

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "正在配置环境并启动安装程序..."
        
        # 【关键步骤】在执行子脚本前，尝试在当前进程加载 brew 环境
        # 这样 install.sh 就能直接继承到 PATH
        BREW_LOCATIONS=(
            "/home/linuxbrew/.linuxbrew/bin/brew"
            "$HOME/.linuxbrew/bin/brew"
        )
        
        for loc in "${BREW_LOCATIONS[@]}"; do
            if [[ -f "$loc" ]]; then
                eval "$($loc shellenv)"
                info "已激活 Homebrew 环境: $loc"
                break
            fi
        done

        # 检查 brew 是否真的可用
        if ! command -v brew &>/dev/null; then
            warn "当前会话仍未找到 brew，install.sh 可能会报错。"
        fi

        # 执行子脚本
        # 这里的引号非常关键，处理 "Run This!" 中的空格
        bash "$TARGET_INSTALL_SCRIPT"
    else
        info "已跳过。你可以随后手动运行: ${YELLOW}bash \"$TARGET_INSTALL_SCRIPT\"${NC}"
    fi
else
    warn "在仓库中未找到 install.sh"
    info "预期路径: $TARGET_INSTALL_SCRIPT"
    
    # 调试：如果没找到，帮用户列出目录结构，方便排查
    info "当前 $DOTFILES_DIR 的目录结构："
    ls -R "$DOTFILES_DIR" | head -n 20
fi