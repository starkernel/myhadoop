#!/bin/bash
# Jenkins 构建脚本 - Bigtop 一键构建
# 用途: 在 centos1 容器中执行 Bigtop 构建

set -e  # 遇到错误立即退出

echo "========================================="
echo "Bigtop 一键构建"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 检查 centos1 容器状态
echo "→ 检查容器状态..."
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行"
    echo ""
    echo "请先启动容器："
    echo "  docker-compose up -d centos1"
    exit 1
fi

echo "✓ centos1 容器运行中"

# 检查构建脚本是否存在
echo ""
echo "→ 检查构建脚本..."
if ! docker exec centos1 test -f /scripts/build/onekey_build.sh; then
    echo "✗ 构建脚本不存在: /scripts/build/onekey_build.sh"
    exit 1
fi

echo "✓ 构建脚本存在"

# 执行构建
echo ""
echo "========================================="
echo "开始执行构建"
echo "========================================="
echo ""

# 注意：不使用 -it 参数，因为 Jenkins 不是 TTY
# 使用 -l 参数启动登录 shell，这样会自动加载 /etc/profile 中的环境变量
docker exec centos1 bash -l /scripts/build/onekey_build.sh

BUILD_EXIT_CODE=$?

echo ""
echo "========================================="
if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "✓ 构建成功！"
else
    echo "✗ 构建失败！退出码: $BUILD_EXIT_CODE"
fi
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

exit $BUILD_EXIT_CODE
