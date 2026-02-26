#!/bin/bash
# 快速修复容器初始化问题

echo "========================================="
echo "快速修复容器初始化"
echo "========================================="

echo ""
echo "问题: Python 编译使用 --enable-optimizations"
echo "影响: 需要运行完整测试套件，耗时 30-60 分钟"
echo "解决: 已禁用优化，编译时间缩短到 5-10 分钟"
echo ""

read -p "是否重启容器应用修复？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消操作"
    exit 0
fi

echo ""
echo "→ 停止容器..."
docker-compose down centos1

echo ""
echo "→ 清理 Python 编译缓存..."
docker run --rm -v /opt/hadoop/ambari-env/scripts:/scripts centos:7.9.2009 \
    bash -c "rm -rf /opt/modules/virtual_env/Python-3.7.12" 2>/dev/null || true

echo ""
echo "→ 启动容器..."
docker-compose up -d centos1

echo ""
echo "========================================="
echo "✓ 容器已重启"
echo "========================================="
echo ""
echo "监控初始化进度:"
echo "  watch -n 10 './check-container-ready.sh'"
echo ""
echo "或查看实时日志:"
echo "  docker logs -f centos1"
echo ""
