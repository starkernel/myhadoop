#!/bin/bash
# Jenkins 构建环境准备脚本
# 用途: 在 centos1 容器中准备构建环境并修复常见问题

set -e

echo "========================================="
echo "准备构建环境"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 检查容器状态
echo "→ 检查容器状态..."
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行，尝试启动..."
    docker start centos1 || {
        echo "✗ 容器启动失败，检查日志..."
        docker logs centos1 --tail 100
        exit 1
    }
    echo "等待容器完全启动..."
    sleep 10
fi
echo "✓ centos1 容器运行中"

# 安装必要的构建工具（包括 patch）
echo ""
echo "→ 安装构建工具..."
docker exec centos1 bash -c "
    set -e
    echo '安装 patch 和其他构建工具...'
    yum install -y patch git wget curl tar gzip bzip2 unzip || true
    
    echo '验证工具安装...'
    which patch && echo '✓ patch 已安装' || echo '✗ patch 安装失败'
    which git && echo '✓ git 已安装' || echo '✗ git 安装失败'
"

# 检查并修复 Ambari 源码目录
echo ""
echo "→ 检查 Ambari 源码..."
docker exec centos1 bash -c "
    # 检查 ambari3 目录
    if [ -d /opt/modules/ambari3 ]; then
        echo '✓ 发现 /opt/modules/ambari3 目录'
        
        # 创建符号链接到 ambari（如果不存在）
        if [ ! -e /opt/modules/ambari ]; then
            echo '创建符号链接: /opt/modules/ambari -> /opt/modules/ambari3'
            ln -sf /opt/modules/ambari3 /opt/modules/ambari
        fi
    elif [ -d /opt/modules/ambari ]; then
        echo '✓ 发现 /opt/modules/ambari 目录'
    else
        echo '✗ Ambari 源码目录不存在'
        echo ''
        echo '提示: 容器启动时会自动从 GitHub 克隆代码'
        echo '如果克隆失败，可以手动克隆：'
        echo '  docker exec centos1 bash -c \"cd /opt/modules && git clone --depth 1 -b branch-3.0.0 https://github.com/apache/ambari.git ambari3\"'
        echo '  docker exec centos1 bash -c \"ln -sf /opt/modules/ambari3 /opt/modules/ambari\"'
        exit 1
    fi
    
    # 显示目录信息
    ls -la /opt/modules/ambari | head -10
"

# 检查其他必要目录
echo ""
echo "→ 检查构建目录..."
docker exec centos1 bash -c "
    mkdir -p /opt/modules
    mkdir -p /opt/bigtop
    mkdir -p /data/rpm-package/ambari
    mkdir -p /root/.m2
    echo '✓ 构建目录已准备'
"

# 验证关键工具
echo ""
echo "→ 验证构建工具..."
docker exec centos1 bash -c "
    echo '检查 Java...'
    java -version 2>&1 | head -1 || echo '✗ Java 未安装'
    
    echo '检查 Maven...'
    mvn -version 2>&1 | head -1 || echo '✗ Maven 未安装'
    
    echo '检查 Patch...'
    patch --version 2>&1 | head -1 || echo '✗ Patch 未安装'
"

echo ""
echo "========================================="
echo "✓ 环境准备完成！"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""
echo "下一步："
echo "  ./jenkins-build-bigtop.sh"
echo ""
