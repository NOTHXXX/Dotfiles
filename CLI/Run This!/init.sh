#!/bin/bash

# 遇到错误立即停止，变量未定义报错，管道错误报错
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
# 1. 系统基础环境与 Homebrew (代理强化版)
# ──────────────────────────────────────────────────
section "System & Homebrew"

# 定义代理地址
PROXY_ADDR="http://192.168.31.10:20172"

info "更新系统软件包列表..."
# 如果 apt 也需要代理，可以在这里临时添加
sudo http_proxy="$PROXY_ADDR" https_proxy="$PROXY_ADDR" apt-get update -y
sudo apt-get install -y build-essential curl git procps file

# 探测 brew 是否已在 PATH 中
if command -v brew &>/dev/null; then
    info "Homebrew 已安装，跳过"
else
    info "正在通过代理安装 Homebrew (官方源)..."
    
    # 【1. 注入环境变量代理】
    export http_proxy="$PROXY_ADDR"
    export https_proxy="$PROXY_ADDR"
    export all_proxy="$PROXY_ADDR"
    
    # 【2. 注入 Git 全局代理】(防止安装脚本内部的 git clone 失败)
    git config --global http.proxy "$PROXY_ADDR"
    git config --global https.proxy "$PROXY_ADDR"
    
    # 执行安装脚本
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 【3. 核心修复】：确定安装路径并立即注入当前 Shell 会话
    BREW_LOCATIONS=(
        "/home/linuxbrew/.linuxbrew/bin/brew"
        "$HOME/.linuxbrew/bin/brew"
    )
    
    SELECTED_BREW=""
    for loc in "${BREW_LOCATIONS[@]}"; do
        if [[ -f "$loc" ]]; then
            SELECTED_BREW="$loc"
            break
        fi
    done

    if [[ -n "$SELECTED_BREW" ]]; then
        # 立即激活当前进程环境
        eval "$($SELECTED_BREW shellenv)"
        
        # 写入 .bashrc
        {
          echo ""
          echo "# Homebrew 环境变量"
          echo "eval \"\$($SELECTED_BREW shellenv)\""
          # 建议在 .bashrc 中也加上代理开关，方便后续使用 brew install
        } >> "$HOME/.bashrc"
        
        info "Homebrew 环境已即时加载并写入 .bashrc"
    else
        die "Homebrew 安装似乎失败，找不到 brew 可执行文件。"
    fi

    # 清理：安装完成后取消 Git 代理（如果你希望后续不走代理）
    # git config --global --unset http.proxy
    # git config --global --unset https.proxy
    unset http_proxy https_proxy all_proxy
fi

# ──────────────────────────────────────────────────
# 2. 拉取 Dotfiles 仓库 (多镜像加速版)
# ──────────────────────────────────────────────────
section "Dotfiles Repository"

DOTFILES_DIR="$HOME/dotfiles"
# 原始地址与常用的 GitHub 国内镜像/加速通道
MIRRORS=(
    "https://github.com/NOTHXXX/Dotfiles.git"
    "https://kkgithub.com/NOTHXXX/Dotfiles.git"
    "https://ghproxy.net/https://github.com/NOTHXXX/Dotfiles.git"
    "https://mirror.ghproxy.com/https://github.com/NOTHXXX/Dotfiles.git"
)
MAX_RETRY=3

if [[ -d "$DOTFILES_DIR" ]]; then
    info "目录 $DOTFILES_DIR 已存在，尝试更新..."
    cd "$DOTFILES_DIR"
    # 尝试拉取更新，如果失败则不强制停止脚本（避免因为网络抖动中断初始化）
    git pull || warn "Git pull 失败，请稍后手动更新。"
else
    info "正在克隆仓库..."
    SUCCESS=false
    
    # 遍历镜像列表
    for REPO_URL in "${MIRRORS[@]}"; do
        info "尝试从 $REPO_URL 克隆..."
        
        for i in $(seq 1 $MAX_RETRY); do
            if git clone "$REPO_URL" "$DOTFILES_DIR"; then
                info "克隆成功！"
                SUCCESS=true
                break 2 # 跳出两层循环
            fi
            warn "第 $i 次克隆失败，5秒后重试..."
            sleep 5
        done
        
        warn "当前镜像源不可用，尝试下一个..."
    done

    if [ "$SUCCESS" = false ]; then
        die "所有镜像源均克隆失败，请检查服务器网络。"
    fi
fi

# ──────────────────────────────────────────────────
# 3. SSH 配置 (固定公钥授权)
# ──────────────────────────────────────────────────
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
sudo systemctl enable ssh --now || warn "无法启动 SSH 服务，可能在容器环境下运行"

# ──────────────────────────────────────────────────
# 4. 运行安装脚本 (环境继承版)
# ──────────────────────────────────────────────────
section "Next Steps"

# 注意：仓库中的路径包含空格，变量引用时必须带引号
TARGET_INSTALL_SCRIPT="$DOTFILES_DIR/CLI/Run This!/install.sh"

if [[ -f "$TARGET_INSTALL_SCRIPT" ]]; then
    echo -ne "${YELLOW}所有前置准备完成。是否立即运行 $TARGET_INSTALL_SCRIPT? (y/n, 30s后默认y): ${NC}"
    
    # 处理 curl | bash 管道下的输入问题
    if [[ -t 0 ]]; then
        read -r -t 30 response || response="y"
    else
        read -r -t 30 response < /dev/tty || response="y"
    fi

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "正在启动安装程序..."
        
        # 由于上面已经执行了 eval shellenv，当前进程已拥有 brew 环境变量
        # 直接执行子脚本，子脚本会继承这些环境变量
        bash "$TARGET_INSTALL_SCRIPT"
    else
        info "已跳过。你可以随后手动运行: ${YELLOW}bash \"$TARGET_INSTALL_SCRIPT\"${NC}"
    fi
else
    warn "在仓库中未找到安装脚本"
    info "预期路径: $TARGET_INSTALL_SCRIPT"
fi

info "脚本执行完毕！"