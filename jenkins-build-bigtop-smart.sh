#!/bin/bash
# Jenkins 构建脚本 - 智能断点续传版本
# 用途: 主动检查每个 Bigtop 组件的完成状态，只构建未完成的组件
set -eo pipefail

# Gradle 内存配置（支持大型项目如 Flink）
export GRADLE_OPTS="${GRADLE_OPTS} -Xms2g -Xmx8g -XX:MaxMetaspaceSize=1g -XX:+HeapDumpOnOutOfMemoryError"

echo "========================================="
echo "Bigtop 智能断点续传构建"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Gradle 内存: 最大堆 8GB, Metaspace 1GB"
echo "========================================="

# 检查容器状态
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行"
    exit 1
fi

BUILD_SUCCESS=true
BUILD_START_TIME=$(date +%s)

# 1. Ambari 构建
echo ""
echo "[1/4] Ambari 构建"
AMBARI_COUNT=$(docker exec centos1 find /data/rpm-package/ambari -name "*.rpm" 2>/dev/null | wc -l)
if [ "$AMBARI_COUNT" -ge 5 ]; then
    echo "✓ 已完成 ($AMBARI_COUNT 个 RPM)"
else
    if docker exec centos1 bash -l -c "/scripts/build/ambari/build_ambari_all.sh"; then
        echo "✓ 构建完成"
    else
        echo "✗ 构建失败"
        BUILD_SUCCESS=false
    fi
fi

# 2. Bigtop 组件构建（智能断点续传）
if [ "$BUILD_SUCCESS" = true ]; then
    echo ""
    echo "[2/4] Bigtop 组件构建（智能模式）"
    
    # 定义所有组件及其 RPM 包名称模式
    declare -A COMPONENTS=(
        ["bigtop-groovy"]="bigtop-groovy"
        ["bigtop-jsvc"]="bigtop-jsvc"
        ["bigtop-select"]="bigtop-select"
        ["bigtop-utils"]="bigtop-utils"
        ["zookeeper"]="zookeeper_3_2_0"
        ["hadoop"]="hadoop"
        ["flink"]="flink"
        ["hbase"]="hbase"
        ["hive"]="hive"
        ["kafka"]="kafka"
        ["spark"]="spark"
        ["solr"]="solr"
        ["tez"]="tez"
        ["zeppelin"]="zeppelin"
        ["livy"]="livy"
        ["sqoop"]="sqoop"
        ["ranger"]="ranger"
        ["redis"]="redis"
        ["phoenix"]="phoenix"
        ["dolphinscheduler"]="dolphinscheduler"
    )
    
    # 检查哪些组件已完成
    COMPLETED=()
    PENDING=()
    
    for component in "${!COMPONENTS[@]}"; do
        rpm_pattern="${COMPONENTS[$component]}"
        rpm_count=$(docker exec centos1 find /data/rpm-package/bigtop -name "${rpm_pattern}*.rpm" 2>/dev/null | wc -l)
        if [ "$rpm_count" -gt 0 ]; then
            COMPLETED+=("$component")
        else
            PENDING+=("$component")
        fi
    done
    
    echo ""
    echo "已完成组件 (${#COMPLETED[@]}): ${COMPLETED[*]}"
    echo "待构建组件 (${#PENDING[@]}): ${PENDING[*]}"
    
    if [ "${#PENDING[@]}" -eq 0 ]; then
        echo "✓ 所有 Bigtop 组件已完成"
    else
        echo ""
        echo "→ 开始构建待完成的组件..."
        
        # 应用所有补丁
        docker exec centos1 bash -c "
            cd /opt/modules/bigtop
            for patch_script in /scripts/build/bigtop/build1_0_*.sh; do
                if [ -f \"\$patch_script\" ]; then
                    echo \"应用补丁: \$patch_script\"
                    bash \"\$patch_script\" || true
                fi
            done
        "
        
        # 构建待完成的组件（添加 -rpm 后缀）
        GRADLE_TASKS=()
        for component in "${PENDING[@]}"; do
            GRADLE_TASKS+=("${component}-rpm")
        done
        
        echo ""
        echo "→ 执行: gradle ${GRADLE_TASKS[*]}"
        
        if docker exec centos1 bash -l -c "
            source /opt/rh/devtoolset-7/enable
            cd /opt/modules/bigtop
            ./gradlew ${GRADLE_TASKS[*]} -PparentDir=/usr/bigtop -Dbuildwithdeps=true -PpkgSuffix 2>&1 | tee gradle_resume.log
        "; then
            echo "✓ Bigtop 组件构建完成"
            
            # 复制 RPM 包
            docker exec centos1 bash -c "
                cd /opt/modules/bigtop
                for dir in output/*; do
                    if [ -d \"\$dir\" ]; then
                        component=\$(basename \"\$dir\")
                        mkdir -p /data/rpm-package/bigtop/\$component
                        find \"\$dir\" -name '*.rpm' -not -name '*.src.rpm' -exec cp -v {} /data/rpm-package/bigtop/\$component/ \;
                    fi
                done
            "
        else
            echo "✗ Bigtop 组件构建失败"
            BUILD_SUCCESS=false
        fi
    fi
fi

# 3. Ambari Infra
if [ "$BUILD_SUCCESS" = true ]; then
    echo ""
    echo "[3/4] Ambari Infra 构建"
    if docker exec centos1 test -f "/scripts/build/ambari-infra/build.sh"; then
        if docker exec centos1 bash -l -c "/scripts/build/ambari-infra/build.sh"; then
            echo "✓ 构建完成"
        else
            echo "✗ 构建失败"
            BUILD_SUCCESS=false
        fi
    else
        echo "○ 构建脚本不存在，跳过"
    fi
fi

# 4. Ambari Metrics
if [ "$BUILD_SUCCESS" = true ]; then
    echo ""
    echo "[4/4] Ambari Metrics 构建"
    if docker exec centos1 test -f "/scripts/build/ambari-metrics/build.sh"; then
        if docker exec centos1 bash -l -c "/scripts/build/ambari-metrics/build.sh"; then
            echo "✓ 构建完成"
        else
            echo "✗ 构建失败"
            BUILD_SUCCESS=false
        fi
    else
        echo "○ 构建脚本不存在，跳过"
    fi
fi

# 结果汇总
BUILD_END_TIME=$(date +%s)
TOTAL_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))

echo ""
echo "========================================="
if [ "$BUILD_SUCCESS" = true ]; then
    echo "✓ 所有构建任务完成"
    echo "总耗时: $(($TOTAL_DURATION / 60))m $(($TOTAL_DURATION % 60))s"
    
    # 统计 RPM
    docker exec centos1 bash -c "
        total=\$(find /data/rpm-package -name '*.rpm' 2>/dev/null | wc -l)
        size=\$(find /data/rpm-package -name '*.rpm' -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo \"RPM 包: \$total 个 (\$size)\"
    "
    exit 0
else
    echo "✗ 构建失败"
    echo "已运行: $(($TOTAL_DURATION / 60))m"
    echo ""
    echo "重新运行此脚本将自动跳过已完成的组件"
    exit 1
fi
