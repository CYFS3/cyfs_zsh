#!/bin/bash
# deploy_arm64.sh — 兼容入口（ARM64 专用旧接口）
# 新版 deploy.sh 会自动检测操作系统和架构，本脚本仅为兼容旧用法保留，
# 内部转发到统一的 deploy.sh。
# 用法: bash deploy_arm64.sh

set -euo pipefail

cur_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] deploy_arm64.sh 为兼容入口，转发到统一的 deploy.sh ..."
exec bash "${cur_dir}/deploy.sh" "$@"
