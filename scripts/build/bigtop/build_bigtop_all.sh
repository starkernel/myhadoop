#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: JaneTTR

set -e

# 确保 cmake 可用（Hadoop 编译需要）
if ! command -v cmake &> /dev/null; then
    echo "cmake not found, installing..."
    yum install -y cmake
fi

echo "Using cmake version: $(cmake --version | head -1)"



echo "############## ONE_KEY_BUILD start #############"

# 清理可能存在的 Gradle Daemon 进程
echo "→ 检查并清理 Gradle Daemon..."
if pgrep -f "GradleDaemon" > /dev/null 2>&1; then
    echo "  发现运行中的 Gradle Daemon，正在停止..."
    pkill -9 -f "GradleDaemon" || true
    sleep 3
    echo "  ✓ Gradle Daemon 已强制停止"
else
    echo "  ✓ 无运行中的 Gradle Daemon"
fi

# 清理 Daemon 日志文件（防止累积）
echo "→ 清理 Gradle Daemon 日志..."
rm -rf /root/.gradle/daemon/*/daemon-*.out.log 2>/dev/null || true
rm -rf ~/.gradle/daemon/*/daemon-*.out.log 2>/dev/null || true
echo "  ✓ Daemon 日志已清理"

# 从 Docker Compose 网络中获取 Nexus IP
export NEXUS_URL="nexus"

# 兼容旧的 .lock 文件方式
if [ -f "/scripts/system/before/nexus/.lock" ]; then
    export NEXUS_URL=$(cat /scripts/system/before/nexus/.lock)
fi

export NEXUS_USERNAME="admin"
export NEXUS_PASSWORD="admin123"
echo $NEXUS_URL

PROJECT_PATH="/opt/modules/bigtop"
RPM_PACKAGE="/data/rpm-package/bigtop"
mkdir -p "$RPM_PACKAGE"



echo "1.0.0 补丁"
bash /scripts/build/bigtop/build.sh

echo "1.0.1 补丁"
bash /scripts/build/bigtop/build1_0_1.sh

echo "1.0.2 补丁"
bash /scripts/build/bigtop/build1_0_2.sh

echo "1.0.3 补丁"
bash /scripts/build/bigtop/build1_0_3.sh

echo "1.0.4 补丁"
bash /scripts/build/bigtop/build1_0_4.sh

echo "1.0.5 补丁"
bash /scripts/build/bigtop/build1_0_5.sh

echo "1.0.6 补丁"
bash /scripts/build/bigtop/build1_0_6.sh

echo "1.0.7 补丁"
bash /scripts/build/bigtop/build1_0_7.sh


# 开启 gcc 高版本
source /opt/rh/devtoolset-7/enable

cd "$PROJECT_PATH"

# Gradle 内存配置（支持大型项目如 Flink）
export GRADLE_OPTS="-Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC"
# 强制禁用 Gradle Daemon（避免后台进程持续运行）
export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.daemon=false"

# 覆盖项目中的 gradle.properties（强制禁用 Daemon）
echo "→ 配置 gradle.properties 禁用 Daemon..."
cat > "$PROJECT_PATH/gradle.properties" << 'EOF'
# Gradle JVM 参数 - 增加内存以支持 Flink 等大型项目构建
org.gradle.jvmargs=-Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError

# 强制禁用 Gradle daemon（避免后台进程和日志累积）
org.gradle.daemon=false

# 禁用并行构建（避免内存竞争）
org.gradle.parallel=false

# 配置文件缓存
org.gradle.caching=true
EOF

# 同时在用户目录创建（全局生效）
mkdir -p ~/.gradle
cat > ~/.gradle/gradle.properties << 'EOF'
org.gradle.daemon=false
org.gradle.jvmargs=-Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC
EOF

echo "✓ gradle.properties 已配置（Daemon 强制禁用）"
echo "Gradle 内存配置: 最大堆 16GB, Metaspace 2GB, Daemon 强制禁用"

# 定义所有组件列表，并标注版本历史
ALL_COMPONENTS=(
  # 1.0.0 版本
  bigtop-groovy-rpm
  bigtop-jsvc-rpm
  bigtop-select-rpm
  bigtop-utils-rpm
  zookeeper-rpm
  hadoop-rpm
  flink-rpm
  hbase-rpm
  hive-rpm
  kafka-rpm
  spark-rpm
  solr-rpm
  tez-rpm
  zeppelin-rpm
  livy-rpm
  # 1.0.1 版本新增
  sqoop-rpm
  ranger-rpm
  # 1.0.2 版本新增
  redis-rpm
  # 1.0.3 版本新增
  phoenix-rpm
  dolphinscheduler-rpm
  # 1.0.4 版本新增
  doris-download
  # 1.0.5 版本新增
  nightingale-download
  categraf-download
  victoriametrics-download
  cloudbeaver-download
  celeborn-download
  ozone-download
  impala-download
  # 1.0.6 版本新增
  hudi-download
  paimon-download
  # 1.0.7 版本新增
  atlas-download
  superset-download
)

# 编译所有组件
echo "=========================================="
echo "开始 Gradle 构建"
echo "=========================================="
echo "日志文件: $PROJECT_PATH/gradle_build.log"
echo "日志级别: WARN（只显示警告和错误）"
echo "测试: 跳过（-x test）"
echo "Daemon: 禁用（--no-daemon）"
echo "=========================================="

# 清理旧日志（避免追加导致日志无限增长）
rm -f "$PROJECT_PATH/gradle_build.log"

# Gradle 构建参数说明：
# --no-daemon: 禁用 Gradle Daemon（避免后台进程）
# --max-workers=4: 限制并行任务数（避免内存峰值）
# --warn: 只显示警告和错误（减少日志输出）
# -x test: 跳过所有测试任务（大幅减少构建时间和日志）
# --console=plain: 使用纯文本输出（避免进度条刷新产生大量日志）
gradle "${ALL_COMPONENTS[@]}" \
  -PparentDir=/usr/bigtop \
  -Dbuildwithdeps=true \
  -PpkgSuffix \
  --no-daemon \
  --max-workers=4 \
  --warn \
  -x test \
  --console=plain \
  2>&1 | tee "$PROJECT_PATH/gradle_build.log"

# 检查 Gradle 构建结果
GRADLE_EXIT_CODE=${PIPESTATUS[0]}
if [ $GRADLE_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "=========================================="
    echo "✗ Gradle 构建失败 (退出码: $GRADLE_EXIT_CODE)"
    echo "=========================================="
    echo "完整日志: $PROJECT_PATH/gradle_build.log"
    LOG_SIZE=$(du -h "$PROJECT_PATH/gradle_build.log" 2>/dev/null | cut -f1 || echo "未知")
    echo "日志大小: $LOG_SIZE"
    echo ""
    echo "最后 50 行错误信息："
    tail -50 "$PROJECT_PATH/gradle_build.log" | grep -E "ERROR|FAILURE|Exception|BUILD FAILED" || tail -50 "$PROJECT_PATH/gradle_build.log"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ Gradle 构建成功"
echo "=========================================="
LOG_SIZE=$(du -h "$PROJECT_PATH/gradle_build.log" 2>/dev/null | cut -f1 || echo "未知")
echo "日志大小: $LOG_SIZE"


# 遍历 output 目录下的每个子目录
for dir in "$PROJECT_PATH"/output/*; do
    if [ -d "$dir" ]; then
        # 获取子目录的名称
        component=$(basename "$dir")

        # 创建目标目录
        mkdir -p "$RPM_PACKAGE/$component"

        # 查找并复制文件
        find "$dir" -iname '*.rpm' -not -iname '*.src.rpm' -exec cp -rv {} "$RPM_PACKAGE/$component" \;
    fi
done


echo "=========================================="
echo "清理 Gradle Daemon 和临时文件"
echo "=========================================="

# 停止 Gradle Daemon
cd "$PROJECT_PATH"
./gradlew --stop 2>/dev/null || true
sleep 2

# 强制杀死可能残留的 Daemon 进程
pkill -9 -f "GradleDaemon" 2>/dev/null || true
sleep 1

# 清理 Daemon 日志文件（防止下次累积）
echo "→ 清理 Daemon 日志文件..."
rm -rf /root/.gradle/daemon/*/daemon-*.out.log 2>/dev/null || true
rm -rf ~/.gradle/daemon/*/daemon-*.out.log 2>/dev/null || true
rm -rf "$PROJECT_PATH/.gradle/daemon" 2>/dev/null || true

# 显示清理结果
DAEMON_COUNT=$(pgrep -f "GradleDaemon" | wc -l)
if [ "$DAEMON_COUNT" -eq 0 ]; then
    echo "✓ 所有 Daemon 进程已清理"
else
    echo "⚠ 仍有 $DAEMON_COUNT 个 Daemon 进程运行"
fi

echo "✓ 清理完成"

echo "############## ONE_KEY_BUILD end #############"
