#!/bin/bash
# Flink 构建监控脚本

echo "=========================================="
echo "Flink 构建状态监控"
echo "=========================================="
echo ""

# 检查进程
PID_FILE="/tmp/flink_v5.pid"
LOG_FILE="/tmp/flink_v5.log"

if [ -f "$PID_FILE" ]; then
    PID=$(cat $PID_FILE)
    if docker exec centos1 ps -p $PID > /dev/null 2>&1; then
        RUNTIME=$(docker exec centos1 ps -p $PID -o etime= | tr -d ' ')
        echo "✓ 构建进程正在运行"
        echo "  PID: $PID"
        echo "  运行时间: $RUNTIME"
    else
        echo "✗ 构建进程已停止"
        echo "  检查日志查看是成功还是失败"
    fi
else
    echo "✗ 没有找到构建进程"
fi

echo ""
echo "=========================================="
echo "日志文件信息"
echo "=========================================="
docker exec centos1 bash -c "ls -lh $LOG_FILE 2>/dev/null || echo '日志文件不存在'"

echo ""
echo "=========================================="
echo "最新日志（最后 30 行）"
echo "=========================================="
docker exec centos1 tail -30 $LOG_FILE 2>/dev/null || echo "无法读取日志"

echo ""
echo "=========================================="
echo "错误检查"
echo "=========================================="
ERROR_COUNT=$(docker exec centos1 grep -c '\[ERROR\]' $LOG_FILE 2>/dev/null || echo "0")
if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "⚠ 发现 $ERROR_COUNT 个错误"
    echo ""
    echo "最近的错误："
    docker exec centos1 grep '\[ERROR\]' $LOG_FILE 2>/dev/null | tail -5
else
    echo "✓ 暂无错误"
fi

echo ""
echo "=========================================="
echo "构建进度提示"
echo "=========================================="
echo "Flink 完整构建预计需要 20-30 分钟"
echo "可以运行此脚本随时查看进度："
echo "  bash check_flink_build.sh"
echo ""
