#!/bin/bash
# Jenkins 构建脚本 - Bigtop 智能构建
# 用途: 在 Jenkins 环境中执行 Bigtop 构建，支持断点续传

set -e

# Gradle 内存配置（支持大型项目如 Flink）
export GRADLE_OPTS="${GRADLE_OPTS} -Xms2g -Xmx8g -XX:MaxMetaspaceSize=1g -XX:+HeapDumpOnOutOfMemoryError"

echo "========================================="
echo "Bigtop 智能构建（支持断点续传）"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Jenkins Job: ${JOB_NAME:-本地运行}"
echo "Build Number: ${BUILD_NUMBER:-N/A}"
echo "Gradle 内存: 最大堆 8GB, Metaspace 1GB"
echo "========================================="

# 构建状态检查函数
check_ambari_completed() {
    local rpm_count=$(docker exec centos1 find /data/rpm-package/ambari -name "*.rpm" 2>/dev/null | wc -l)
    [ "$rpm_count" -ge 5 ]  # 至少需要 5 个主要的 RPM 包
}

check_bigtop_progress() {
    local completed_rpms=$(docker exec centos1 find /data/rpm-package -name "*.rpm" -path "*bigtop*" 2>/dev/null | wc -l)
    [ "$completed_rpms" -gt 0 ]
}

get_failed_gradle_tasks() {
    docker exec centos1 bash -c "
        if [ -f /opt/modules/bigtop/.last_failed_task ]; then
            cat /opt/modules/bigtop/.last_failed_task
        fi
    " 2>/dev/null || echo ""
}

mark_stage_completed() {
    local stage=$1
    docker exec centos1 touch "/tmp/build_${stage}_completed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $stage 构建完成"
}

check_stage_completed() {
    local stage=$1
    docker exec centos1 test -f "/tmp/build_${stage}_completed" 2>/dev/null
}

# 检查容器状态
echo "→ 检查容器状态..."
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行，尝试启动..."
    docker-compose up -d centos1
    sleep 15
    
    # 再次检查
    if ! docker ps | grep -q centos1; then
        echo "✗ 容器启动失败"
        exit 1
    fi
fi
echo "✓ centos1 容器运行中"

# 检查构建脚本
echo ""
echo "→ 检查构建脚本..."
if ! docker exec centos1 test -f /scripts/build/onekey_build.sh; then
    echo "✗ 构建脚本不存在: /scripts/build/onekey_build.sh"
    exit 1
fi
echo "✓ 构建脚本存在"

# 分析构建状态
echo ""
echo "→ 分析构建状态..."

BUILD_PLAN=""
SKIP_AMBARI=false
SKIP_BIGTOP=false
RESUME_BIGTOP=false
FAILED_TASKS=""

# 1. Ambari 状态检查
echo ""
echo "1. Ambari 构建状态："
if check_ambari_completed; then
    rpm_count=$(docker exec centos1 find /data/rpm-package/ambari -name "*.rpm" 2>/dev/null | wc -l)
    echo "  ✓ 已完成 ($rpm_count 个 RPM 包)"
    BUILD_PLAN="${BUILD_PLAN}□ Ambari: 跳过（已完成）\n"
    SKIP_AMBARI=true
else
    echo "  → 需要构建"
    BUILD_PLAN="${BUILD_PLAN}■ Ambari: 需要构建\n"
fi

# 2. Bigtop 组件状态检查（细粒度）
echo ""
echo "2. Bigtop 组件构建状态："

# 定义 Bigtop 核心组件列表（按构建顺序）
BIGTOP_COMPONENTS=(
    "hadoop"
    "zookeeper"
    "hbase"
    "spark"
    "flink"
    "kafka"
    "hive"
    "tez"
)

COMPLETED_COMPONENTS=()
PENDING_COMPONENTS=()
FAILED_COMPONENT=""

# 检查每个组件的构建状态
for component in "${BIGTOP_COMPONENTS[@]}"; do
    # 检查 RPM 是否存在
    rpm_count=$(docker exec centos1 find /data/rpm-package -name "${component}-*.rpm" 2>/dev/null | wc -l)
    
    if [ "$rpm_count" -gt 0 ]; then
        echo "  ✓ $component: 已完成 ($rpm_count 个 RPM)"
        COMPLETED_COMPONENTS+=("$component")
        BUILD_PLAN="${BUILD_PLAN}□ $component: 跳过（已完成）\n"
    else
        echo "  → $component: 待构建"
        PENDING_COMPONENTS+=("$component")
        BUILD_PLAN="${BUILD_PLAN}■ $component: 需要构建\n"
    fi
done

# 检查是否有失败的组件
if docker exec centos1 test -f "/tmp/bigtop_last_failed_component" 2>/dev/null; then
    FAILED_COMPONENT=$(docker exec centos1 cat /tmp/bigtop_last_failed_component 2>/dev/null)
    if [ -n "$FAILED_COMPONENT" ]; then
        echo "  ⚠ 上次失败组件: $FAILED_COMPONENT"
    fi
fi

# 判断构建策略
if [ ${#PENDING_COMPONENTS[@]} -eq 0 ]; then
    echo "  ✓ 所有组件已完成"
    SKIP_BIGTOP=true
elif [ ${#COMPLETED_COMPONENTS[@]} -gt 0 ]; then
    echo "  → 断点续传模式: 从 ${PENDING_COMPONENTS[0]} 开始"
    RESUME_BIGTOP=true
else
    echo "  → 完整构建模式"
fi

# 3. 其他组件状态
echo ""
echo "3. 其他组件状态："
for stage in "ambari-infra" "ambari-metrics"; do
    if check_stage_completed "$stage"; then
        echo "  ✓ $stage 已完成"
        BUILD_PLAN="${BUILD_PLAN}□ $stage: 跳过（已完成）\n"
    else
        echo "  → $stage 待构建"
        BUILD_PLAN="${BUILD_PLAN}■ $stage: 需要构建\n"
    fi
done

# 显示构建计划
echo ""
echo "========================================="
echo "构建执行计划："
echo "========================================="
echo -e "$BUILD_PLAN"

# 开始构建（无需用户确认）
echo ""
echo "========================================="
echo "开始执行构建（自动模式）"
echo "========================================="

BUILD_SUCCESS=true
BUILD_START_TIME=$(date +%s)

# 1. Ambari 构建
if [ "$SKIP_AMBARI" = false ]; then
    echo ""
    echo "→ [1/4] 构建 Ambari..."
    STAGE_START=$(date +%s)
    
    if docker exec centos1 bash -l -c "/scripts/build/ambari/build_ambari_all.sh"; then
        STAGE_END=$(date +%s)
        STAGE_DURATION=$((STAGE_END - STAGE_START))
        mark_stage_completed "ambari"
        echo "✓ Ambari 构建完成 (耗时: ${STAGE_DURATION}s)"
    else
        echo "✗ Ambari 构建失败"
        BUILD_SUCCESS=false
    fi
else
    echo ""
    echo "□ [1/4] Ambari 已跳过"
fi

# 2. Bigtop 构建
if [ "$BUILD_SUCCESS" = true ] && [ "$SKIP_BIGTOP" = false ]; then
    echo ""
    STAGE_START=$(date +%s)
    
    if [ "$RESUME_BIGTOP" = true ]; then
        echo "→ [2/4] 断点续传 Bigtop 构建..."
        echo "重试任务: $FAILED_TASKS"
        
        # 清理失败标记
        docker exec centos1 bash -c "
            cd /opt/modules/bigtop
            rm -f .last_failed_task .gradle_build_failed
        "
        
        # 重试失败的任务
        if docker exec centos1 bash -l -c "
            cd /opt/modules/bigtop
            ./gradlew --continue $FAILED_TASKS 2>&1 | tee -a gradle_retry.log
        "; then
            STAGE_END=$(date +%s)
            STAGE_DURATION=$((STAGE_END - STAGE_START))
            mark_stage_completed "bigtop"
            echo "✓ Bigtop 断点续传完成 (耗时: ${STAGE_DURATION}s)"
        else
            echo "✗ Bigtop 断点续传失败"
            BUILD_SUCCESS=false
        fi
    else
        echo "→ [2/4] 构建 Bigtop..."
        
        if docker exec centos1 bash -l -c "/scripts/build/bigtop/build_bigtop_all.sh"; then
            STAGE_END=$(date +%s)
            STAGE_DURATION=$((STAGE_END - STAGE_START))
            mark_stage_completed "bigtop"
            echo "✓ Bigtop 构建完成 (耗时: ${STAGE_DURATION}s)"
        else
            echo "✗ Bigtop 构建失败"
            # 记录失败信息
            docker exec centos1 bash -c "
                cd /opt/modules/bigtop
                touch .gradle_build_failed
                # 尝试提取最后失败的任务
                if [ -f gradle_build.log ]; then
                    grep 'FAILED' gradle_build.log | tail -1 | sed 's/.*Task ://' | sed 's/ FAILED.*//' > .last_failed_task 2>/dev/null || true
                fi
            "
            BUILD_SUCCESS=false
        fi
    fi
else
    echo ""
    echo "□ [2/4] Bigtop 已跳过"
fi

# 3. 其他组件构建
if [ "$BUILD_SUCCESS" = true ]; then
    stage_num=3
    for stage in "ambari-infra" "ambari-metrics"; do
        if ! check_stage_completed "$stage"; then
            echo ""
            echo "→ [$stage_num/4] 构建 $stage..."
            STAGE_START=$(date +%s)
            
            if docker exec centos1 test -f "/scripts/build/$stage/build.sh"; then
                if docker exec centos1 bash -l -c "/scripts/build/$stage/build.sh"; then
                    STAGE_END=$(date +%s)
                    STAGE_DURATION=$((STAGE_END - STAGE_START))
                    mark_stage_completed "$stage"
                    echo "✓ $stage 构建完成 (耗时: ${STAGE_DURATION}s)"
                else
                    echo "✗ $stage 构建失败"
                    BUILD_SUCCESS=false
                    break
                fi
            else
                echo "○ $stage 构建脚本不存在，跳过"
            fi
        else
            echo ""
            echo "□ [$stage_num/4] $stage 已跳过"
        fi
        stage_num=$((stage_num + 1))
    done
fi

# 构建结果汇总
BUILD_END_TIME=$(date +%s)
TOTAL_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))

echo ""
echo "========================================="
echo "构建结果汇总"
echo "========================================="

if [ "$BUILD_SUCCESS" = true ]; then
    echo "✓ 构建成功！"
    echo "总耗时: ${TOTAL_DURATION}s ($(($TOTAL_DURATION / 60))m $(($TOTAL_DURATION % 60))s)"
    
    # 统计构建产物
    echo ""
    echo "构建产物统计："
    docker exec centos1 bash -c "
        ambari_rpms=\$(find /data/rpm-package/ambari -name '*.rpm' 2>/dev/null | wc -l)
        bigtop_rpms=\$(find /data/rpm-package -name '*.rpm' -path '*bigtop*' 2>/dev/null | wc -l)
        total_rpms=\$(find /data/rpm-package -name '*.rpm' 2>/dev/null | wc -l)
        
        echo \"  Ambari RPM: \$ambari_rpms 个\"
        echo \"  Bigtop RPM: \$bigtop_rpms 个\"
        echo \"  总计 RPM: \$total_rpms 个\"
        
        if [ \$total_rpms -gt 0 ]; then
            total_size=\$(find /data/rpm-package -name '*.rpm' -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
            echo \"  总大小: \$total_size\"
        fi
    "
    
    BUILD_EXIT_CODE=0
else
    echo "✗ 构建失败！"
    echo "已运行时间: ${TOTAL_DURATION}s"
    echo ""
    echo "Jenkins 故障排查："
    echo "1. 重新运行此 Job - 将自动跳过已完成的部分"
    echo "2. 查看 Console Output 中的详细错误信息"
    echo "3. 检查容器日志: docker logs centos1 | tail -100"
    echo "4. 如需手动调试: docker exec -it centos1 bash"
    
    BUILD_EXIT_CODE=1
fi

echo ""
echo "构建完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Jenkins Job: ${JOB_NAME:-未知} #${BUILD_NUMBER:-未知}"
echo "========================================="

exit $BUILD_EXIT_CODE