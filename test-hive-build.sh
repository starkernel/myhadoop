#!/bin/bash
# 测试 Hive 单独构建脚本
set -eo pipefail

echo "========================================="
echo "Hive 单独构建测试"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 检查容器状态
echo "→ 检查容器状态..."
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行"
    exit 1
fi
echo "✓ centos1 容器运行中"

echo ""
echo "→ 开始构建 Hive..."
echo "  日志: /opt/modules/bigtop/hive_test.log"
echo ""

START_TIME=$(date +%s)

if docker exec centos1 bash -c "
    cd /opt/modules/bigtop
    ./gradlew hive-rpm 2>&1 | tee /opt/modules/bigtop/hive_test.log
"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "✓ Hive 构建成功！"
    echo "  耗时: $(($DURATION / 60))m $(($DURATION % 60))s"
    
    echo ""
    echo "→ 检查生成的 RPM 包:"
    docker exec centos1 bash -c "
        if [ -d /data/rpm-package/bigtop/hive ]; then
            rpm_count=\$(find /data/rpm-package/bigtop/hive -name '*.rpm' -not -name '*.src.rpm' | wc -l)
            echo \"  RPM 数量: \$rpm_count\"
            if [ \$rpm_count -gt 0 ]; then
                echo \"  RPM 列表:\"
                find /data/rpm-package/bigtop/hive -name '*.rpm' -not -name '*.src.rpm' -exec basename {} \; | sed 's/^/    /'
            fi
        fi
    "
    
    EXIT_CODE=0
else
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "✗ Hive 构建失败"
    echo "  已运行: $(($DURATION / 60))m $(($DURATION % 60))s"
    echo ""
    echo "查看错误日志:"
    echo "  docker exec centos1 tail -100 /opt/modules/bigtop/hive_test.log"
    
    EXIT_CODE=1
fi

echo ""
echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

exit $EXIT_CODE
