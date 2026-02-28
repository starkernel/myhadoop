#!/bin/bash
# Jenkins 构建脚本 - Bigtop CI 构建（组件级断点续传优化版）
# 用途: 在 Jenkins 环境中执行 Bigtop 构建，支持组件级断点续传
set -eo pipefail

echo "========================================="
echo "Bigtop CI 构建（组件级断点续传）"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Jenkins Job: ${JOB_NAME:-未知}"
echo "Build Number: ${BUILD_NUMBER:-未知}"
echo "========================================="

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

# 构建状态检查函数
check_ambari_completed() {
    local rpm_count=$(docker exec centos1 find /data/rpm-package/ambari -name "*.rpm" 2>/dev/null | wc -l)
    [ "$rpm_count" -ge 5 ] && return 0 || return 1
}

check_component_completed() {
    local component=$1
    local rpm_count=$(docker exec centos1 find /data/rpm-package -name "${component}-*.rpm" 2>/dev/null | wc -l)
    [ "$rpm_count" -gt 0 ] && return 0 || return 1
}

mark_stage_completed() {
    local stage=$1
    docker exec centos1 touch "/tmp/build_${stage}_completed"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $stage 构建完成"
}

check_stage_completed() {
    local stage=$1
    docker exec centos1 test -f "/tmp/build_${stage}_completed" 2>/dev/null && return 0 || return 1
}

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

# 分析构建状态
echo ""
echo "→ 分析构建状态..."
BUILD_PLAN=""
SKIP_AMBARI=false
COMPLETED_COMPONENTS=()
PENDING_COMPONENTS=()

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

for component in "${BIGTOP_COMPONENTS[@]}"; do
    if check_component_completed "$component"; then
        rpm_count=$(docker exec centos1 find /data/rpm-package -name "${component}-*.rpm" 2>/dev/null | wc -l)
        echo "  ✓ $component: 已完成 ($rpm_count 个 RPM)"
        COMPLETED_COMPONENTS+=("$component")
        BUILD_PLAN="${BUILD_PLAN}□ $component: 跳过（已完成）\n"
    else
        echo "  → $component: 待构建"
        PENDING_COMPONENTS+=("$component")
        BUILD_PLAN="${BUILD_PLAN}■ $component: 需要构建\n"
    fi
done

# 检查上次失败的组件
FAILED_COMPONENT=""
if docker exec centos1 test -f "/tmp/bigtop_last_failed_component" 2>/dev/null; then
    FAILED_COMPONENT=$(docker exec centos1 cat /tmp/bigtop_last_failed_component 2>/dev/null)
    if [ -n "$FAILED_COMPONENT" ]; then
        echo ""
        echo "  ⚠ 上次失败组件: $FAILED_COMPONENT"
        echo "  → 将从 $FAILED_COMPONENT 开始重新构建"
    fi
fi

# 显示构建计划
echo ""
echo "========================================="
echo "构建执行计划："
echo "========================================="
echo -e "$BUILD_PLAN"
echo ""
if [ "${#COMPLETED_COMPONENTS[@]}" -gt 0 ]; then
    echo "已完成: ${COMPLETED_COMPONENTS[*]}"
fi
if [ "${#PENDING_COMPONENTS[@]}" -gt 0 ]; then
    echo "待构建: ${PENDING_COMPONENTS[*]}"
else
    echo "✓ 所有 Bigtop 组件已完成"
fi

# 开始构建
echo ""
echo "========================================="
echo "开始执行构建（自动模式）"
echo "========================================="
BUILD_SUCCESS=true
BUILD_START_TIME=$(date +%s)

# 1. Ambari 构建
if [ "$SKIP_AMBARI" = false ]; then
    echo ""
    echo "→ [1/3] 构建 Ambari..."
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
    echo "□ [1/3] Ambari 已跳过"
fi

# 2. Bigtop 组件构建（逐个构建）
if [ "$BUILD_SUCCESS" = true ]; then
    pending_count=${#PENDING_COMPONENTS[@]}
    if [ "$pending_count" -gt 0 ]; then
        echo ""
        echo "→ [2/3] Bigtop 组件构建（断点续传模式）"
        echo "待构建组件数: $pending_count"
        
        BIGTOP_START=$(date +%s)
        component_index=1
        total_components=$pending_count
        
        for component in "${PENDING_COMPONENTS[@]}"; do
            echo ""
            echo "→ [$component_index/$total_components] 构建组件: $component"
            COMPONENT_START=$(date +%s)
            
            # 记录当前构建的组件
            docker exec centos1 bash -c "echo '$component' > /tmp/bigtop_current_component"
            
            # 执行组件构建（捕获失败但不立即退出）
            if docker exec centos1 bash -l -c "cd /opt/modules/bigtop && ./gradlew ${component}-pkg 2>&1 | tee gradle_${component}.log"; then
                COMPONENT_END=$(date +%s)
                COMPONENT_DURATION=$((COMPONENT_END - COMPONENT_START))
                echo "✓ $component 构建完成 (耗时: ${COMPONENT_DURATION}s / $(($COMPONENT_DURATION / 60))m)"
                
                # 清理失败标记
                docker exec centos1 rm -f /tmp/bigtop_last_failed_component /tmp/bigtop_current_component
            else
                echo "✗ $component 构建失败"
                # 记录失败的组件
                FAILED_COMPONENT="$component"
                docker exec centos1 bash -c "echo '$component' > /tmp/bigtop_last_failed_component"
                BUILD_SUCCESS=false
                break
            fi
            
            component_index=$((component_index + 1))
        done
        
        if [ "$BUILD_SUCCESS" = true ]; then
            BIGTOP_END=$(date +%s)
            BIGTOP_DURATION=$((BIGTOP_END - BIGTOP_START))
            mark_stage_completed "bigtop"
            echo ""
            echo "✓ Bigtop 所有组件构建完成 (总耗时: ${BIGTOP_DURATION}s / $(($BIGTOP_DURATION / 60))m)"
        fi
    else
        echo ""
        echo "□ [2/3] Bigtop 所有组件已完成"
    fi
fi

# 3. 其他组件构建
if [ "$BUILD_SUCCESS" = true ]; then
    stage_num=3
    for stage in "ambari-infra" "ambari-metrics"; do
        if ! check_stage_completed "$stage"; then
            echo ""
            echo "→ [$stage_num/3] 构建 $stage..."
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
            echo "□ [$stage_num/3] $stage 已跳过"
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
    
    # 显示各组件构建时间
    echo ""
    echo "组件构建详情："
    for component in "${BIGTOP_COMPONENTS[@]}"; do
        if check_component_completed "$component"; then
            rpm_count=$(docker exec centos1 find /data/rpm-package -name "${component}-*.rpm" 2>/dev/null | wc -l)
            echo "  ✓ $component: $rpm_count 个 RPM"
        fi
    done
    
    BUILD_EXIT_CODE=0
else
    echo "✗ 构建失败！"
    echo "已运行时间: ${TOTAL_DURATION}s ($(($TOTAL_DURATION / 60))m)"
    echo ""
    echo "失败信息："
    if [ -n "$FAILED_COMPONENT" ]; then
        echo "  失败组件: $FAILED_COMPONENT"
    fi
    echo ""
    echo "Jenkins 故障排查："
    echo "1. 重新运行此 Job - 将自动从失败的组件继续"
    echo "2. 查看 Console Output 中的详细错误信息"
    echo "3. 检查组件日志: docker exec centos1 cat /opt/modules/bigtop/gradle_${FAILED_COMPONENT}.log"
    echo "4. 如需手动调试: docker exec -it centos1 bash"
    echo ""
    echo "已完成的组件: ${COMPLETED_COMPONENTS[*]}"
    echo "下次构建将跳过已完成的组件"
    
    BUILD_EXIT_CODE=1
fi

echo ""
echo "构建完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Jenkins Job: ${JOB_NAME:-未知} #${BUILD_NUMBER:-未知}"
echo "========================================="

exit $BUILD_EXIT_CODE
