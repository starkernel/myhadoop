#!/bin/bash
# 检查 centos1 容器是否准备就绪

echo "检查 centos1 容器初始化状态..."
echo "========================================"

# 检查容器是否运行
if ! docker ps | grep -q centos1; then
    echo "✗ 容器未运行"
    exit 1
fi
echo "✓ 容器正在运行"

# 检查初始化进度
echo ""
echo "初始化进度："
docker logs centos1 2>&1 | grep "##.*end" | sed 's/.*##/  ✓/'

# 检查是否有进程在下载
echo ""
if docker exec centos1 pgrep -x curl > /dev/null 2>&1; then
    echo "⏳ 正在下载文件..."
    docker exec centos1 ps aux | grep curl | grep -v grep | awk '{print "   ", $11, $12, $13}'
fi

if docker exec centos1 pgrep -x wget > /dev/null 2>&1; then
    echo "⏳ 正在下载文件..."
    docker exec centos1 ps aux | grep wget | grep -v grep | awk '{print "   ", $11, $12, $13}'
fi

if docker exec centos1 pgrep -x yum > /dev/null 2>&1; then
    echo "⏳ yum 正在安装软件包..."
fi

# 检查 SSH 服务
echo ""
if docker exec centos1 pgrep -x sshd > /dev/null 2>&1; then
    echo "✓ SSH 服务已启动 - 容器初始化完成！"
    exit 0
else
    echo "⏳ 容器仍在初始化中，请等待..."
    exit 1
fi
