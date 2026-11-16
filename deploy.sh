#!/bin/bash
# deploy.sh — CYFS Zsh 环境一键部署脚本（单脚本全流程）
# 自动检测操作系统 (Linux/macOS) 与 CPU 架构 (x86_64/arm64)，
# 自动获取仓库资源（本地仓库或自动 clone），安装 zsh 与依赖，
# 部署 Oh My Zsh + Powerlevel10k + zplug + fzf。
# 已有配置一律不覆盖：本机 .zshrc/.oh-my-zsh/.zplug/.fzf/.p10k.zsh 保留，
# 通过 ~/.cyfs_zshrc 链接加载共享配置。
# 本机环境保存在 ~/.config/cyfs-zsh/local.zsh，已有 .zshrc 在共享配置后执行。
#
# 用法:
#   本地一键:   bash deploy.sh [--no-chsh] [--repo <path>]
#   在线一键:   curl -fsSL https://raw.githubusercontent.com/CYFS3/cyfs_zsh/main/deploy.sh | bash
#   远程设备:   由 connect_and_install_cyfs_zsh.sh 调用
#
# 选项:
#   --no-chsh        不修改默认 shell
#   --repo <path>    指定 cyfs_zsh 仓库路径（默认: 脚本所在目录，其次 ~/cyfs_zsh）

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# ──────────────────────────────────────────────
# 0. 参数解析
# ──────────────────────────────────────────────
DO_CHSH=true
REPO_PATH=""

usage() {
    echo "用法: $0 [--no-chsh] [--repo <path>]"
    echo ""
    echo "选项:"
    echo "  --no-chsh        不修改默认 shell"
    echo "  --repo <path>    cyfs_zsh 仓库路径"
    echo "  -h, --help       显示此帮助信息"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-chsh)      DO_CHSH=false; shift ;;
        --repo|-r)      REPO_PATH="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *)              log_error "未知参数: $1"; usage ;;
    esac
done

# ──────────────────────────────────────────────
# 1. 用户检测 — 不能用 root 直接装配置
# ──────────────────────────────────────────────
REAL_USER=""
REAL_HOME=""

if [[ $EUID -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$SUDO_USER")
    log_info "以 sudo 运行，实际目标用户: $REAL_USER ($REAL_HOME)"
elif [[ $EUID -eq 0 ]]; then
    log_error "请勿直接以 root 运行此脚本。应以普通用户运行："
    log_error "  bash $0 [--repo <path>]"
    log_error "脚本内部的 apt/brew 操作会自动使用 sudo。"
    exit 1
else
    REAL_USER="${USER:-$(whoami)}"
    REAL_HOME="$HOME"
fi

# 覆盖 HOME，确保部署到正确用户目录
export HOME="$REAL_HOME"
export USER="$REAL_USER"

# ──────────────────────────────────────────────
# 2. 定位仓库资源
#    curl | bash 在线执行时脚本不在仓库内，自动 clone 到 ~/cyfs_zsh
# ──────────────────────────────────────────────
log_step "定位 cyfs_zsh 仓库..."

if [[ -n "$REPO_PATH" ]]; then
    if [[ ! -d "$REPO_PATH" ]]; then
        log_error "指定的仓库路径不存在: $REPO_PATH"
        exit 1
    fi
elif [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/.fzf.tgz" ]]; then
    # 脚本在仓库目录内直接运行（bash deploy.sh）
    REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -d "$REAL_HOME/cyfs_zsh" ]] && [[ -f "$REAL_HOME/cyfs_zsh/.fzf.tgz" ]]; then
    REPO_PATH="$REAL_HOME/cyfs_zsh"
else
    log_info "未找到本地仓库，自动 clone 到 $REAL_HOME/cyfs_zsh ..."
    if [[ -e "$REAL_HOME/cyfs_zsh" ]]; then
        log_error "目标路径已存在，请使用 --repo 指定仓库，避免覆盖已有文件。"
        exit 1
    fi
    if ! git clone --depth 1 https://github.com/CYFS3/cyfs_zsh.git "$REAL_HOME/cyfs_zsh"; then
        log_error "自动 clone 失败，请检查网络或使用 --repo 指定本地仓库。"
        exit 1
    fi
    REPO_PATH="$REAL_HOME/cyfs_zsh"
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
log_info "仓库路径: $REPO_PATH"

# ──────────────────────────────────────────────
# 3. OS 检测
# ──────────────────────────────────────────────
log_step "检测操作系统..."

OS_NAME="$(uname -s)"

case "$OS_NAME" in
    Linux)
        if command -v apt &>/dev/null; then
            PKG_MANAGER="apt"
        elif command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
        elif command -v yum &>/dev/null; then
            PKG_MANAGER="yum"
        else
            PKG_MANAGER="unknown"
        fi
        log_info "Linux 系统，包管理器: $PKG_MANAGER"
        ;;
    Darwin)
        if ! command -v brew &>/dev/null; then
            log_error "未找到 Homebrew (brew)。请先安装: https://brew.sh"
            exit 1
        fi
        PKG_MANAGER="brew"
        log_info "macOS 系统，包管理器: brew"
        ;;
    *)
        log_error "不支持的操作系统: $OS_NAME（仅支持 Linux/macOS）"
        exit 1
        ;;
esac

# ──────────────────────────────────────────────
# 4. 架构检测
# ──────────────────────────────────────────────
log_step "检测 CPU 架构..."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)   ARCH_LABEL="x86_64 (AMD64)" ;;
    aarch64|arm64)  ARCH_LABEL="ARM64 (aarch64)" ;;
    *)
        log_error "不支持的 CPU 架构: $ARCH（仅支持 x86_64 / arm64）"
        exit 1
        ;;
esac

log_info "平台: $OS_NAME / $ARCH_LABEL"

# ──────────────────────────────────────────────
# 5. 检查 Zsh
# ──────────────────────────────────────────────
log_step "检查 Zsh..."

if command -v zsh &>/dev/null; then
    log_info "Zsh 已安装: $(which zsh) ($(zsh --version 2>/dev/null || echo unknown))"
else
    log_warn "Zsh 未安装，尝试安装..."
    case "$PKG_MANAGER" in
        apt)  sudo apt update && sudo apt install -y zsh ;;
        dnf)  sudo dnf install -y zsh ;;
        yum)  sudo yum install -y zsh ;;
        brew) brew install zsh ;;
        *)    log_error "无法自动安装 zsh，请手动安装后重试。"; exit 1 ;;
    esac
fi

# ──────────────────────────────────────────────
# 6. 检查其他依赖 (git / tar)
# ──────────────────────────────────────────────
log_step "检查依赖..."

MISSING_DEPS=()
for dep in git tar python3; do
    command -v "$dep" &>/dev/null || MISSING_DEPS+=("$dep")
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    log_warn "缺少依赖: ${MISSING_DEPS[*]}"
    case "$PKG_MANAGER" in
        apt)  sudo apt update && sudo apt install -y "${MISSING_DEPS[@]}" ;;
        brew) brew install "${MISSING_DEPS[@]}" ;;
        *)    log_error "请手动安装: ${MISSING_DEPS[*]}"; exit 1 ;;
    esac
fi

log_info "依赖检查通过 (git, tar)"

# ──────────────────────────────────────────────
# 7. 备份现有配置（若稍后需要覆盖时使用）
# ──────────────────────────────────────────────
log_step "备份现有配置..."

for cfg in .zshrc .p10k.zsh .cyfs_zshrc; do
    if [[ -f "$HOME/$cfg" ]]; then
        BACKUP="$HOME/$cfg.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$HOME/$cfg" "$BACKUP"
        log_info "已备份 ~/$cfg → $BACKUP"
    fi
done

# ──────────────────────────────────────────────
# 8. 部署基础组件（已有内容一律不覆盖）
# ──────────────────────────────────────────────
log_step "部署基础组件..."

if [ ! -d "${HOME}/.fzf" ]; then
    tar -xf "$REPO_PATH/.fzf.tgz" -C "${HOME}/"
else
    echo "[INFO] ~/.fzf 已存在，跳过解压（保留本机安装）"
fi

if [ ! -d "${HOME}/.oh-my-zsh" ]; then
    tar -xf "$REPO_PATH/.oh-my-zsh.tgz" -C "${HOME}/"
else
    echo "[INFO] ~/.oh-my-zsh 已存在，跳过解压（保留本机安装）"
fi

if [ ! -d "${HOME}/.zplug" ]; then
    tar -xf "$REPO_PATH/.zplug.tgz" -C "${HOME}/"
else
    echo "[INFO] ~/.zplug 已存在，跳过解压（保留本机安装）"
fi

# 自定义配置层: 仓库 .zshrc 作为独立文件 ~/.cyfs_zshrc
# 统一策略（所有场景一致）：本机 .zshrc 永远保留，只在文件第一行插入一行 source。
# source 置顶 → 共享配置先加载，本机后续配置可覆盖；且与其他工具写入
# .zshrc 的内容互不干扰。
# 链接共享配置，本机环境在独立文件中追加加载。
ln -sfn "$REPO_PATH/.zshrc" "${HOME}/.cyfs_zshrc"
python3 - "$REAL_HOME" <<'PYRC'
from pathlib import Path
import os
import re
import sys
home = Path(sys.argv[1])
rc = home / '.zshrc'
original = rc.read_text() if rc.exists() else ''
start, end = '# >>> cyfs_zsh >>>', '# <<< cyfs_zsh <<<'
managed = '''# >>> cyfs_zsh >>>
typeset -U path
path=("$HOME/.local/bin" "$HOME/.fzf/bin" $path)
[[ ! -r "$HOME/.cyfs_zshrc" ]] || source "$HOME/.cyfs_zshrc"
[[ ! -r "${XDG_CONFIG_HOME:-$HOME/.config}/cyfs-zsh/local.zsh" ]] || source "${XDG_CONFIG_HOME:-$HOME/.config}/cyfs-zsh/local.zsh"
# <<< cyfs_zsh <<<
'''
if start in original or end in original:
    if original.count(start) != 1 or original.count(end) != 1 or original.index(start) > original.index(end):
        raise SystemExit('Invalid cyfs_zsh markers in ~/.zshrc')
    updated = re.sub(re.escape(start) + r'.*?' + re.escape(end) + r'\n?', lambda _: managed, original, flags=re.S)
else:
    updated = managed + original
if updated != original:
    rc.write_text(updated)
config = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config'))) / 'cyfs-zsh'
config.mkdir(parents=True, exist_ok=True)
local = config / 'local.zsh'
if not local.exists():
    local.write_text('# 本机的代理、PATH 与工具链函数写在这里，不提交到 Git。\n')
    local.chmod(0o600)
profile = home / '.zprofile'
profile_text = profile.read_text() if profile.exists() else ''
profile_line = '[[ ! -r "$HOME/.profile" ]] || source "$HOME/.profile"'
if profile_line not in profile_text:
    profile.write_text(profile_line + '\n' + profile_text)
PYRC

# p10k 主题配置: 已有则不覆盖
if [ ! -f "${HOME}/.p10k.zsh" ]; then
    cp "$REPO_PATH/.p10k.zsh" "${HOME}/.p10k.zsh"
    echo "[INFO] 已安装 ~/.p10k.zsh"
else
    echo "[INFO] ~/.p10k.zsh 已存在，跳过覆盖（保留本机配置）"
fi

# ──────────────────────────────────────────────
# 9. 平台相关: fzf 二进制 / gitstatusd / 系统依赖
# ──────────────────────────────────────────────
if [[ "$OS_NAME" == "Darwin" ]]; then
    # ── macOS (ARM64 / x86_64) ──
    echo "[INFO] macOS 平台: 使用 Homebrew 安装依赖"
    BREW_PREFIX="$(brew --prefix)"
    for pkg in fd highlight fzf; do
        # fzf 可能已存在于 ~/.fzf/bin（PATH 中可能排前），故用 brew 前缀判断
        if [[ "$pkg" == "fzf" ]]; then
            [[ -x "$BREW_PREFIX/bin/fzf" ]] && continue
        elif command -v "$pkg" >/dev/null 2>&1; then
            continue
        fi
        echo "[INFO] 安装 $pkg (brew)..."
        brew install "$pkg"
    done
    # 用 brew 的 fzf 覆盖仓库内/既有的 fzf 入口，避免架构不匹配
    if [[ -x "$BREW_PREFIX/bin/fzf" ]]; then
        ln -sf "$BREW_PREFIX/bin/fzf" "${HOME}/.fzf/bin/fzf"
    fi
    # gitstatusd 无 macOS 官方二进制，p10k 会自动回退为慢速 git 状态
    echo "[WARN] gitstatusd 无 macOS 版本，跳过（Powerlevel10k 将回退为慢速 git 状态模式）"
else
    # ── Linux (Ubuntu/Debian) ──
    mkdir -p "${HOME}/.cache/gitstatus"
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        tar -xf "$REPO_PATH/gitstatusd-linux-x86_64.tar.gz" -C "${HOME}/.cache/gitstatus"
    else
        tar -xf "$REPO_PATH/gitstatusd-linux-aarch64.tar.gz" -C "${HOME}/.cache/gitstatus"
        # 用仓库内 ARM64 fzf 二进制覆盖 x86 版
        if compgen -G "$REPO_PATH/fzf-*-linux_arm64.tar.gz" >/dev/null; then
            tar -xf $REPO_PATH/fzf-*-linux_arm64.tar.gz -C "${HOME}/.fzf/bin/"
        else
            echo "[WARN] 未找到 ARM64 fzf 压缩包，跳过 fzf 二进制替换" >&2
        fi
    fi

    echo "[INFO] Linux 平台: 通过 apt 安装系统依赖"
    if ! command -v fdfind >/dev/null 2>&1 || ! command -v highlight >/dev/null 2>&1; then
        sudo apt update
    fi
    if ! command -v fdfind >/dev/null 2>&1; then
        sudo apt install -y fd-find
    fi
    if ! command -v highlight >/dev/null 2>&1; then
        sudo apt install -y highlight
    fi
    if ! command -v fd >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    fi
fi

# ──────────────────────────────────────────────
# 10. fzf shell 集成 (key bindings / completion)
#     Linux: 仓库内 fzf 二进制版本为 0.39.0，直接运行 fzf/install 生成 ~/.fzf.zsh
#     macOS: brew 版 fzf 版本与 0.39.0 不一致，fzf/install 的版本校验会触发
#             网络下载，故手动生成 ~/.fzf.zsh（复用仓库内 shell 集成文件）
# ──────────────────────────────────────────────
cd "${HOME}"
if [[ "$OS_NAME" == "Darwin" ]]; then
    # 确保 shell 集成文件存在（~/.fzf 已存在但可能缺文件时从仓库 tarball 提取）
    for sf in shell/completion.zsh shell/key-bindings.zsh; do
        if [[ ! -f "${HOME}/.fzf/$sf" ]]; then
            echo "[INFO] 从仓库 tarball 提取缺失的 ~/.fzf/$sf ..."
            tar -xf "$REPO_PATH/.fzf.tgz" -C "${HOME}/" ".fzf/$sf"
        fi
    done
    cat > "${HOME}/.fzf.zsh" << EOF
# Setup fzf
# ---------
if [[ ! "\$PATH" == *\$HOME/.fzf/bin* ]]; then
  PATH="\${PATH:+\${PATH}:}\$HOME/.fzf/bin"
fi

# Auto-completion
# ---------------
[[ \$- == *i* ]] && source "\$HOME/.fzf/shell/completion.zsh" 2> /dev/null

# Key bindings
# ------------
source "\$HOME/.fzf/shell/key-bindings.zsh"
EOF
    echo "[INFO] 已生成 ~/.fzf.zsh (macOS)"
else
    "${HOME}/.fzf/install" --key-bindings --completion --no-update-rc
fi

# ──────────────────────────────────────────────
# 11. 设置默认 shell (可选)
# ──────────────────────────────────────────────
if $DO_CHSH; then
    log_step "设置默认 shell..."

    ZSH_PATH="$(which zsh)"

    CURRENT_SHELL="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_shell)')"
    if [[ "$CURRENT_SHELL" == "$ZSH_PATH" ]]; then
        log_info "当前默认 shell 已是 zsh: $ZSH_PATH"
    else
        if grep -qFx "$ZSH_PATH" /etc/shells 2>/dev/null; then
            log_info "将默认 shell 切换为 zsh: $ZSH_PATH"
            if [[ "$EUID" -eq 0 ]]; then
                chsh -s "$ZSH_PATH" "$SUDO_USER" 2>/dev/null || \
                    log_warn "无法修改 shell，请手动执行: chsh -s $ZSH_PATH"
            else
                chsh -s "$ZSH_PATH" 2>/dev/null || \
                    log_warn "无法修改 shell，请手动执行: chsh -s $ZSH_PATH"
            fi
        else
            if [[ "$PKG_MANAGER" == "brew" ]]; then
                # macOS: brew 安装的 zsh 默认不在 /etc/shells，先追加再切换
                log_warn "$ZSH_PATH 不在 /etc/shells 中，尝试追加..."
                if echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null; then
                    log_info "已追加 $ZSH_PATH 到 /etc/shells"
                    chsh -s "$ZSH_PATH" 2>/dev/null && \
                        log_info "默认 shell 已切换为 zsh" || \
                        log_warn "无法修改 shell，请手动执行: chsh -s $ZSH_PATH"
                else
                    log_warn "无法修改 /etc/shells，请手动执行:"
                    log_warn "  echo '$ZSH_PATH' | sudo tee -a /etc/shells"
                    log_warn "  chsh -s $ZSH_PATH"
                fi
            else
                log_warn "$ZSH_PATH 不在 /etc/shells 中，跳过 chsh。"
                log_warn "请手动添加并切换:"
                log_warn "  echo '$ZSH_PATH' | sudo tee -a /etc/shells"
                log_warn "  chsh -s $ZSH_PATH"
            fi
        fi
    fi
else
    log_info "跳过默认 shell 设置 (--no-chsh)"
fi

# 安装仓库自带字体；SSH 客户端仍需在本地安装并选择相同字体。
if [[ "$OS_NAME" == "Linux" ]] && command -v fc-cache >/dev/null; then
    mkdir -p "$HOME/.local/share/fonts"
    cp "$REPO_PATH/Hack Regular Nerd Font Complete Windows Compatible.ttf" "$HOME/.local/share/fonts/"
    fc-cache -f "$HOME/.local/share/fonts"
fi

# ──────────────────────────────────────────────
# 12. 摘要
# ──────────────────────────────────────────────
echo ""
echo "=============================================="
echo -e "${GREEN}  CYFS Zsh 环境部署完成${NC}"
echo "=============================================="
echo ""
echo "操作系统:   $OS_NAME"
echo "CPU 架构:   $ARCH_LABEL"
echo "仓库路径:   $REPO_PATH"
echo "Zsh 路径:   $(which zsh)"
echo "默认 Shell:  $(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_shell)')"
echo ""
echo "下一步:"
echo "  1. 重新登录或执行: exec zsh"
if [[ "$OS_NAME" == "Darwin" ]]; then
    echo "  2. 安装 Hack Nerd Font (如 Powerlevel10k 图标乱码):"
    echo "     open \"$REPO_PATH/Hack Regular Nerd Font Complete Windows Compatible.ttf\""
else
    echo "  2. 安装 Hack Nerd Font (如 Powerlevel10k 图标乱码):"
    echo "     cp \"$REPO_PATH/Hack Regular Nerd Font Complete Windows Compatible.ttf\" ~/.local/share/fonts/ && fc-cache -fv"
fi
echo "  3. 首次启动将自动加载 zplug 插件"
echo ""
echo "常用快捷键:"
echo "  Ctrl+T    fzf 文件搜索"
echo "  Ctrl+R    fzf 历史命令搜索"
echo "  Ctrl+K    删除到行尾"
echo "  Ctrl+U    删除到行首"
echo "=============================================="
