#!/bin/bash
# Jenkins 构建脚本 - Hadoop Ambari Bigtop 环境
# 用途: 启动 Docker Compose 环境并验证容器状态

set -e  # 遇到错误立即退出

echo "========================================="
echo "开始构建 Hadoop Ambari Bigtop 环境"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 切换到项目目录
cd /opt/hadoop/ambari-env/

# 确保 Nexus 数据目录权限正确
echo "→ 修复 Nexus 数据目录权限..."
chown -R 200:200 common/data/nexus-data/

# 停止并清理旧容器（可选，根据需要启用）
# echo "→ 清理旧容器..."
# docker-compose -f docker-compose.yaml down

# 启动容器
echo "→ 启动 Docker Compose 服务..."
docker-compose -f docker-compose.yaml up -d centos1

# 等待容器启动
echo "→ 等待容器启动..."
sleep 15

# 检查 Nexus 容器状态
echo ""
echo "========================================="
echo "检查容器状态"
echo "========================================="

if docker ps | grep -q nexus; then
    NEXUS_STATUS=$(docker inspect nexus --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    echo "✓ Nexus 容器运行中 (健康状态: $NEXUS_STATUS)"
    
    if [ "$NEXUS_STATUS" != "healthy" ]; then
        echo "⚠ Nexus 还在启动中，可能需要几分钟..."
        echo "  可以通过以下命令查看日志:"
        echo "  docker logs nexus"
    fi
else
    echo "✗ Nexus 容器未运行"
    exit 1
fi

# 检查 CentOS1 容器状态
if docker ps | grep -q centos1; then
    echo "✓ CentOS1 容器运行中"
else
    echo "✗ CentOS1 容器未运行"
    exit 1
fi

# 显示所有相关容器
echo ""
echo "========================================="
echo "当前运行的容器"
echo "========================================="
docker ps --filter "name=nexus" --filter "name=centos" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "========================================="
echo "构建完成！"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""
echo "访问地址:"
echo "  - Nexus: http://localhost:8081"
echo "  - CentOS1 SSH: ssh root@localhost -p 22223"
echo ""
