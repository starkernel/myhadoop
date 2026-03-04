#!/bin/bash
# Jenkins 构建脚本 - 优化版（增量构建 + 日志控制）
# 特性：
# 1. 真正的增量构建：已完成的组件不重新构建
# 2. 跳过所有测试：大幅减少构建时间和日志
# 3. 日志级别控制：减少 Maven 输出
set -eo pipefail

# Gradle 和 Maven 内存配置
export GRADLE_OPTS="${GRADLE_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC -Dorg.gradle.daemon=false"
# Maven 全局配置：跳过测试、减少日志
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC"
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true"

echo "========================================="
echo "Bigtop 优化构建（增量 + 跳过测试）"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Jenkins Job: ${JOB_NAME:-未知}"
echo "Build Number: ${BUILD_NUMBER:-未知}"
echo "========================================="
echo "内存配置："
echo "  - Gradle: 最大堆 16GB, Metaspace 2GB"
echo "  - Maven: 最大堆 16GB, Metaspace 2GB"
echo "优化配置："
echo "  - 跳过所有测试（maven.test.skip=true）"
echo "  - 日志级别: WARN"
echo "  - 禁用: rat, checkstyle, enforcer"
echo "========================================="

# 检查容器状态
echo "→ 检查容器状态..."
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行，尝试启动..."
    docker-compose up -d centos1
    sleep 15
    if ! docker ps | grep -q centos1; then
        echo "✗ 容器启动失败"
        exit 1
    fi
fi
echo "✓ centos1 容器运行中"

# 构建配置
BUILD_SUCCESS=true
BUILD_START_TIME=$(date +%s)

# 1. Ambari 构建
echo ""
echo "========================================="
echo "[1/4] Ambari 构建"
echo "========================================="

AMBARI_RPM_COUNT=$(docker exec centos1 find /data/rpm-package/ambari -name "*.rpm" 2>/dev/null | wc -l)
if [ "$AMBARI_RPM_COUNT" -ge 5 ]; then
    echo "✓ Ambari 已完成 ($AMBARI_RPM_COUNT 个 RPM)，跳过"
else
    echo "→ 开始构建 Ambari..."
    STAGE_START=$(date +%s)
    if docker exec centos1 bash -l -c "/scripts/build/ambari/build_ambari_all.sh"; then
        STAGE_END=$(date +%s)
        echo "✓ Ambari 构建完成 (耗时: $(((STAGE_END - STAGE_START) / 60))m)"
    else
        echo "✗ Ambari 构建失败"
        BUILD_SUCCESS=false
    fi
fi

# 2. Bigtop 增量构建
if [ "$BUILD_SUCCESS" = true ]; then
    echo ""
    echo "========================================="
    echo "[2/4] Bigtop 增量构建"
    echo "========================================="
    
    # 检查已完成的组件
    echo "→ 检查已完成的组件..."
    COMPLETED_COMPONENTS=$(docker exec centos1 bash -c "
        cd /data/rpm-package/bigtop 2>/dev/null || exit 0
        for dir in */; do
            component=\${dir%/}
            rpm_count=\$(find \"\$dir\" -name '*.rpm' -not -name '*.src.rpm' 2>/dev/null | wc -l)
            if [ \$rpm_count -gt 0 ]; then
                echo \"\$component\"
            fi
        done
    ")
    
    if [ -n "$COMPLETED_COMPONENTS" ]; then
        echo "✓ 已完成的组件："
        echo "$COMPLETED_COMPONENTS" | sed 's/^/  - /'
        COMPLETED_COUNT=$(echo "$COMPLETED_COMPONENTS" | wc -l)
        echo "  共 $COMPLETED_COUNT 个组件"
    else
        echo "  无已完成组件"
    fi
    
    echo ""
    echo "→ 开始 Bigtop 构建（Gradle 会自动跳过已完成任务）"
    echo "  完整日志: /opt/modules/bigtop/gradle_build.log"
    echo ""
    
    BIGTOP_START=$(date +%s)
    
    if docker exec centos1 bash -l -c "/scripts/build/bigtop/build_bigtop_all.sh"; then
        BIGTOP_END=$(date +%s)
        BIGTOP_DURATION=$((BIGTOP_END - BIGTOP_START))
        echo ""
        echo "✓ Bigtop 构建完成 (耗时: $(($BIGTOP_DURATION / 60))m $(($BIGTOP_DURATION % 60))s)"
        
        # 显示新完成的组件
        NEW_COMPLETED=$(docker exec centos1 bash -c "
            cd /data/rpm-package/bigtop 2>/dev/null || exit 0
            for dir in */; do
                component=\${dir%/}
                rpm_count=\$(find \"\$dir\" -name '*.rpm' -not -name '*.src.rpm' 2>/dev/null | wc -l)
                if [ \$rpm_count -gt 0 ]; then
                    echo \"\$component\"
                fi
            done
        ")
        NEW_COUNT=$(echo "$NEW_COMPLETED" | wc -l)
        echo "✓ 当前已完成 $NEW_COUNT 个组件"
    else
        echo ""
        echo "✗ Bigtop 构建失败"
        echo ""
        echo "查看详细日志:"
        echo "  docker exec centos1 cat /opt/modules/bigtop/gradle_build.log"
        echo ""
        echo "查看日志大小:"
        echo "  docker exec centos1 du -h /opt/modules/bigtop/gradle_build.log"
        BUILD_SUCCESS=false
    fi
fi

# 3. Ambari Infra 构建
if [ "$BUILD_SUCCESS" = true ]; then
    echo ""
    echo "========================================="
    echo "[3/4] Ambari Infra 构建"
    echo "========================================="
    
    if docker exec centos1 test -f "/scripts/build/ambari-infra/build.sh"; then
        STAGE_START=$(date +%s)
        if docker exec centos1 bash -l -c "/scripts/build/ambari-infra/build.sh"; then
            STAGE_END=$(date +%s)
            echo "✓ Ambari Infra 构建完成 (耗时: $(((STAGE_END - STAGE_START) / 60))m)"
        else
            echo "✗ Ambari Infra 构建失败"
            BUILD_SUCCESS=false
        fi
    else
        echo "○ Ambari Infra 构建脚本不存在，跳过"
    fi
fi

# 4. Ambari Metrics 构建
if [ "$BUILD_SUCCESS" = true ]; then
    echo ""
    echo "========================================="
    echo "[4/4] Ambari Metrics 构建"
    echo "========================================="
    
    if docker exec centos1 test -f "/scripts/build/ambari-metrics/build.sh"; then
        STAGE_START=$(date +%s)
        if docker exec centos1 bash -l -c "/scripts/build/ambari-metrics/build.sh"; then
            STAGE_END=$(date +%s)
            echo "✓ Ambari Metrics 构建完成 (耗时: $(((STAGE_END - STAGE_START) / 60))m)"
        else
            echo "✗ Ambari Metrics 构建失败"
            BUILD_SUCCESS=false
        fi
    else
        echo "○ Ambari Metrics 构建脚本不存在，跳过"
    fi
fi

# 构建结果汇总
BUILD_END_TIME=$(date +%s)
TOTAL_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))

echo ""
echo "========================================="
echo "构建结果汇总"
echo "========================================="

if [ "$BUILD_SUCCESS" = true ]; then
    echo "✓ 所有构建任务完成！"
    echo "总耗时: $(($TOTAL_DURATION / 60))m $(($TOTAL_DURATION % 60))s"
    
    # 统计 RPM 包
    echo ""
    echo "RPM 包统计："
    docker exec centos1 bash -c "
        ambari_count=\$(find /data/rpm-package/ambari -name '*.rpm' 2>/dev/null | wc -l)
        bigtop_count=\$(find /data/rpm-package/bigtop -name '*.rpm' 2>/dev/null | wc -l)
        total_count=\$(find /data/rpm-package -name '*.rpm' 2>/dev/null | wc -l)
        total_size=\$(find /data/rpm-package -name '*.rpm' -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo \"  Ambari: \$ambari_count 个\"
        echo \"  Bigtop: \$bigtop_count 个\"
        echo \"  总计: \$total_count 个 (\$total_size)\"
    "
    
    # 显示日志大小
    echo ""
    echo "日志文件大小："
    docker exec centos1 bash -c "
        if [ -f /opt/modules/bigtop/gradle_build.log ]; then
            log_size=\$(du -h /opt/modules/bigtop/gradle_build.log | cut -f1)
            echo \"  Gradle 日志: \$log_size\"
        fi
    "
    
    EXIT_CODE=0
else
    echo "✗ 构建失败"
    echo "已运行: $(($TOTAL_DURATION / 60))m $(($TOTAL_DURATION % 60))s"
    echo ""
    echo "增量构建说明："
    echo "1. 直接重新运行此脚本"
    echo "2. 已完成的组件会自动跳过"
    echo "3. Gradle 会跳过已完成的任务（显示 UP-TO-DATE）"
    echo "4. 只重新执行失败的任务"
    echo ""
    echo "调试命令："
    echo "  查看 Bigtop 日志: docker exec centos1 cat /opt/modules/bigtop/gradle_build.log | less"
    echo "  查看日志大小: docker exec centos1 du -h /opt/modules/bigtop/gradle_build.log"
    echo "  查看最后错误: docker exec centos1 tail -100 /opt/modules/bigtop/gradle_build.log"
    echo "  手动进入容器: docker exec -it centos1 bash"
    
    EXIT_CODE=1
fi

echo ""
echo "构建完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

exit $EXIT_CODE
