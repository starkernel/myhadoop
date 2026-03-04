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

set -ex

echo "############## PRE BUILD BIGTOP start #############"




#########################
####      PATCH       ###
#########################

# 定义一个包含所有补丁文件路径的数组
patch_files=(
  "/scripts/build/bigtop/patch/patch0-BOM-MIRROR-FIXED.diff"
  "/scripts/build/bigtop/patch/patch1-HADOOP-FIXED.diff"
  "/scripts/build/bigtop/patch/patch2-FLINK-FIXED.diff"
  "/scripts/build/bigtop/patch/patch3-KAFKA-FIXED.diff"
  "/scripts/build/bigtop/patch/patch4-SOLR-FIXED.diff"
  "/scripts/build/bigtop/patch/patch5-TEZ-FIXED.diff"
  "/scripts/build/bigtop/patch/patch6-ZEPPELIN-FIXED.diff"
)
PROJECT_PATH="/opt/modules/bigtop"
RPM_PACKAGE="/data/rpm-package/bigtop"

original_directory=$(pwd)
cd "$PROJECT_PATH"
git checkout .
cd "$original_directory"


mkdir -p "$RPM_PACKAGE"

# 定义一个函数来应用补丁
apply_patch() {
  local patch_file=$1
  if patch -p1 --dry-run -R -d "$PROJECT_PATH" <"$patch_file" >/dev/null 2>&1; then
    echo "补丁：$patch_file 已经应用，跳过"
  else
    if patch -p1 --fuzz=0 --verbose -d "$PROJECT_PATH" <"$patch_file"; then
      echo "补丁：$patch_file 已经成功执行"
    else
      echo "补丁：$patch_file 执行失败"
      exit 1
    fi
  fi
}

# 遍历数组并应用每个补丁文件
for patch_file in "${patch_files[@]}"; do
  apply_patch "$patch_file"
done

#########################
####   CHILD_PATCH    ###
#########################

CHILD_PATH="$PROJECT_PATH/bigtop-packages/src/common"

# Clean up old Flink patch file and build cache (no longer needed for Flink 1.17.2)
echo "=========================================="
echo "清理旧的 Flink 编译优化补丁和构建缓存"
echo "=========================================="

# 清理源文件目录中的旧补丁
if [ -f "$CHILD_PATH/flink/patch0-FLINK-COMPILE-FAST.diff" ]; then
  rm -f "$CHILD_PATH/flink/patch0-FLINK-COMPILE-FAST.diff"
  echo "✓ 已删除源目录中的旧 Flink patch 文件"
fi

# 清理 Flink 构建目录（强制重新构建以应用新配置）
FLINK_BUILD_DIR="$PROJECT_PATH/build/flink"
if [ -d "$FLINK_BUILD_DIR" ]; then
  echo "正在清理 Flink 构建缓存目录..."
  rm -rf "$FLINK_BUILD_DIR"
  echo "✓ 已清理 Flink 构建缓存"
else
  echo "✓ Flink 构建缓存不存在，无需清理"
fi

# 优化 Flink do-component-build（内存和日志配置）
FLINK_DO_BUILD="$CHILD_PATH/flink/do-component-build"
if [ -f "$FLINK_DO_BUILD" ]; then
  echo "优化 Flink do-component-build..."
  
  # 备份原始文件
  if [ ! -f "$FLINK_DO_BUILD.orig" ]; then
    cp "$FLINK_DO_BUILD" "$FLINK_DO_BUILD.orig"
  fi
  
  # 在 set -ex 后添加 Maven 内存和日志优化
  if ! grep -q "Flink Maven 内存配置" "$FLINK_DO_BUILD"; then
    sed -i '/^set -ex$/a\
\
# Flink Maven 内存配置（需要大量内存）\
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g"\
export MAVEN_OPTS="${MAVEN_OPTS} -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError"\
# 跳过测试（大幅减少构建时间和日志）\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"\
# 减少日志输出\
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"\
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true"\
# 跳过前端检查（npm ci-check）\
export MAVEN_OPTS="${MAVEN_OPTS} -Dskip.npm=true"\
# 跳过 test-jar 相关的 assembly（避免 assembly 错误）\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip.exec=true"\
echo "✓ Flink Maven: 最大堆 16GB, 跳过测试, 跳过前端检查, 日志级别 WARN"' "$FLINK_DO_BUILD"
    
    echo "✓ 已添加 Flink Maven 优化配置（跳过测试和前端检查）"
  else
    echo "✓ Flink Maven 优化配置已存在"
  fi
  
  # 修改 mvn 命令：移除 -X (debug)，添加 -q (quiet)，跳过 assembly
  if grep -q "mvn.*install" "$FLINK_DO_BUILD"; then
    # 移除 -X 参数（DEBUG 模式，会产生大量日志）
    sed -i 's/mvn -X /mvn /g' "$FLINK_DO_BUILD"
    sed -i 's/ -X / /g' "$FLINK_DO_BUILD"
    echo "✓ 已移除 Maven -X (DEBUG) 参数"
    
    # 确保有 -q 参数
    if ! grep -q "mvn.*-q" "$FLINK_DO_BUILD"; then
      sed -i 's/mvn /mvn -q /g' "$FLINK_DO_BUILD"
      echo "✓ 已添加 Maven -q (QUIET) 参数"
    fi
  fi
fi

echo "✓ Flink 优化完成"

# 定义一个包含源文件和目标路径的数组
copy_files=(
  "/scripts/build/bigtop/patch/child_patch/patch10-HADOOP-COMPILE-FAST.diff:$CHILD_PATH/hadoop"
  # Flink 1.17.2 patch skipped - build already uses -DskipTests flag
  # "/scripts/build/bigtop/patch/child_patch/patch0-FLINK-COMPILE-FAST.diff:$CHILD_PATH/flink"
  "/scripts/build/bigtop/patch/child_patch/patch2-KAFKA-COMPILE-FAST.diff:$CHILD_PATH/kafka"
  "/scripts/build/bigtop/patch/source/hadoop/yarn-ui-bower.tar.gz:$CHILD_PATH/hadoop"
  "/scripts/build/bigtop/patch/child_patch/patch0-SOLR-COMPILE-FAST.diff:$CHILD_PATH/solr"
  "/scripts/build/bigtop/patch/child_patch/patch6-TEZ-COMPILE-FAST.diff:$CHILD_PATH/tez"
  "/scripts/build/bigtop/patch/child_patch/patch3-ZEPPELIN-COMPILE-FAST.diff:$CHILD_PATH/zeppelin"
  "/scripts/build/bigtop/patch/child_patch/patch2-LIVY-COMPILE-FAST.diff:$CHILD_PATH/livy"
)

# 定义一个函数来复制文件并检测更新
copy_file() {
  local source_file=$1
  local destination_path=$2
  local filename=$(basename "$source_file")
  local dest_file="$destination_path/$filename"
  
  if [ ! -f "$source_file" ]; then
    echo "文件：$source_file 不存在"
    exit 1
  fi
  
  # 检测目标文件是否存在且与源文件不同
  if [ -f "$dest_file" ]; then
    if ! cmp -s "$source_file" "$dest_file"; then
      echo "检测到 $filename 已更新，清理相关构建缓存..."
      # 提取组件名称（如 hadoop, flink 等）
      local component=$(basename "$destination_path")
      local build_dir="$PROJECT_PATH/build/$component"
      if [ -d "$build_dir" ]; then
        echo "清理 $component 的构建目录: $build_dir"
        # 使用 find 命令强制删除，忽略权限和锁定问题
        find "$build_dir" -type f -delete 2>/dev/null || true
        find "$build_dir" -depth -type d -delete 2>/dev/null || true
        # 如果目录仍然存在，尝试强制删除
        if [ -d "$build_dir" ]; then
          rm -rf "$build_dir" 2>/dev/null || true
        fi
        echo "✓ $component 构建缓存已清理"
      fi
    fi
  fi
  
  cp -v "$source_file" "$destination_path"
  echo "文件：$source_file 已成功复制到 $destination_path"
}

# 遍历数组并复制每个文件
for file_pair in "${copy_files[@]}"; do
  IFS=":" read -r source_file destination_path <<<"$file_pair"
  copy_file "$source_file" "$destination_path"
done

# 直接修改 Hadoop do-component-build 添加 Moment.js locale 冲突修复
HADOOP_DO_BUILD="$CHILD_PATH/hadoop/do-component-build"
if [ -f "$HADOOP_DO_BUILD" ]; then
  echo "修改 Hadoop do-component-build 添加 Maven 优化、Moment.js 修复和 Yetus 下载修复..."
  
  # 1. 在 set -ex 后添加 Maven 优化配置
  if ! grep -q "Hadoop Maven 优化配置" "$HADOOP_DO_BUILD"; then
    sed -i '/^set -ex$/a\
\
# Hadoop Maven 优化配置\
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC"\
# 跳过测试（大幅减少构建时间和日志）\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"\
# 减少日志输出\
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"\
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true"\
echo "✓ Hadoop Maven: 最大堆 16GB, 跳过测试, 日志级别 WARN"' "$HADOOP_DO_BUILD"
    
    echo "✓ 已添加 Hadoop Maven 优化配置"
  fi
  
  # 2. 找到bower解压那一行，添加 Moment.js 和 Yetus 修复
  if grep -q "yarn-ui-bower.tar.gz" "$HADOOP_DO_BUILD"; then
    # 创建临时文件
    LINE_NUM=$(grep -n "yarn-ui-bower.tar.gz" "$HADOOP_DO_BUILD" | cut -d: -f1)
    
    # 分割并插入代码
    head -n $LINE_NUM "$HADOOP_DO_BUILD" > "${HADOOP_DO_BUILD}.tmp"
    
    cat >> "${HADOOP_DO_BUILD}.tmp" << 'MOMENT_FIX_CODE'

# Fix Moment.js locale case conflict (en-SG.js vs en-sg.js)
echo "=========================================="
echo "Fixing Moment.js locale case conflict"
echo "=========================================="
MOMENT_BASE_DIR="./hadoop-yarn-project/hadoop-yarn/hadoop-yarn-ui/src/main/webapp/bower_components/moment"
if [ -d "$MOMENT_BASE_DIR" ]; then
    # Remove lowercase en-sg.js from both locale and src/locale directories
    for locale_dir in "$MOMENT_BASE_DIR/locale" "$MOMENT_BASE_DIR/src/locale"; do
        if [ -d "$locale_dir" ]; then
            echo "Checking directory: $locale_dir"
            # Find and remove only the lowercase en-sg.js file
            find "$locale_dir" -name 'en-sg.js' -type f | while read file; do
                echo "Removing conflicting file: $file"
                rm -f "$file"
            done
        fi
    done
    echo "✓ Moment.js locale conflict fixed"
else
    echo "⚠ Warning: Moment bower_components directory not found, skipping fix"
fi

# Fix Yetus download issue (shelldocs dependency)
echo "=========================================="
echo "Fixing Yetus download for shelldocs"
echo "=========================================="
YETUS_VERSION="0.13.0"
YETUS_DIR="$HOME/.yetus"
YETUS_TAR="apache-yetus-${YETUS_VERSION}-bin.tar.gz"
YETUS_EXTRACT_DIR="$YETUS_DIR/apache-yetus-${YETUS_VERSION}"

if [ ! -d "$YETUS_EXTRACT_DIR" ]; then
    echo "Downloading Yetus ${YETUS_VERSION}..."
    mkdir -p "$YETUS_DIR"
    cd "$YETUS_DIR"
    
    # 尝试多个镜像源
    DOWNLOAD_SUCCESS=false
    for MIRROR in \
        "https://archive.apache.org/dist/yetus/${YETUS_VERSION}/${YETUS_TAR}" \
        "https://dlcdn.apache.org/yetus/${YETUS_VERSION}/${YETUS_TAR}" \
        "https://mirrors.tuna.tsinghua.edu.cn/apache/yetus/${YETUS_VERSION}/${YETUS_TAR}" \
        "https://mirrors.aliyun.com/apache/yetus/${YETUS_VERSION}/${YETUS_TAR}"
    do
        echo "Trying mirror: $MIRROR"
        if curl -f -L -o "$YETUS_TAR" "$MIRROR" 2>/dev/null; then
            echo "✓ Downloaded from $MIRROR"
            DOWNLOAD_SUCCESS=true
            break
        else
            echo "✗ Failed to download from $MIRROR"
        fi
    done
    
    if [ "$DOWNLOAD_SUCCESS" = true ]; then
        echo "Extracting Yetus..."
        tar -xzf "$YETUS_TAR"
        rm -f "$YETUS_TAR"
        echo "✓ Yetus installed to $YETUS_EXTRACT_DIR"
    else
        echo "⚠ Warning: Failed to download Yetus, shelldocs may fail"
    fi
    
    cd -
else
    echo "✓ Yetus already installed at $YETUS_EXTRACT_DIR"
fi

# 设置 Yetus 环境变量（shelldocs 会使用）
if [ -d "$YETUS_EXTRACT_DIR" ]; then
    export YETUS_HOME="$YETUS_EXTRACT_DIR"
    export PATH="$YETUS_EXTRACT_DIR/bin:$PATH"
    echo "✓ Yetus environment configured"
fi
MOMENT_FIX_CODE
    
    tail -n +$((LINE_NUM + 1)) "$HADOOP_DO_BUILD" >> "${HADOOP_DO_BUILD}.tmp"
    mv "${HADOOP_DO_BUILD}.tmp" "$HADOOP_DO_BUILD"
    chmod +x "$HADOOP_DO_BUILD"
    
    echo "✓ Hadoop do-component-build 已添加 Moment.js locale 冲突修复和 Yetus 下载修复"
  else
    echo "⚠ 未找到 bower tar.gz 行，跳过修改"
  fi
fi

#########################
####      BUILD       ###
#########################

#########################
#### MAVEN CLEANUP    ###
#########################

# 清理Maven本地仓库中的失败标记文件
echo "=========================================="
echo "清理 Maven 本地仓库失败标记"
echo "=========================================="

docker exec centos1 bash -c "
  # 清理 aws-java-sdk-bundle 的失败标记
  find /root/.m2/repository/com/amazonaws/aws-java-sdk-bundle/ -name '*.lastUpdated' -delete 2>/dev/null || true
  echo '✓ 已清理 aws-java-sdk-bundle 失败标记'
  
  # 手动下载 aws-java-sdk-bundle jar包（绕过maven-public超时问题）
  AWS_JAR_DIR='/root/.m2/repository/com/amazonaws/aws-java-sdk-bundle/1.12.262'
  AWS_JAR_FILE='\${AWS_JAR_DIR}/aws-java-sdk-bundle-1.12.262.jar'
  
  if [ ! -f \"\${AWS_JAR_FILE}\" ] || [ ! -s \"\${AWS_JAR_FILE}\" ]; then
    echo '正在从 maven-releases 下载 aws-java-sdk-bundle...'
    mkdir -p \"\${AWS_JAR_DIR}\"
    cd \"\${AWS_JAR_DIR}\"
    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
      curl -f -o aws-java-sdk-bundle-1.12.262.jar \
      http://nexus:8081/repository/maven-releases/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar \
      && echo '✓ aws-java-sdk-bundle 下载成功' \
      || echo '⚠ aws-java-sdk-bundle 下载失败'
    
    # 下载后再次清理失败标记
    find /root/.m2/repository/com/amazonaws/aws-java-sdk-bundle/ -name '*.lastUpdated' -delete 2>/dev/null || true
  else
    echo '✓ aws-java-sdk-bundle 已存在，跳过下载'
  fi
" 2>/dev/null || true

#########################
#### MAVEN TIMEOUT    ###
#########################

# 设置Maven HTTP超时参数（解决大文件如aws-java-sdk-bundle下载超时问题）
echo "=========================================="
echo "配置 Maven HTTP 超时参数"
echo "=========================================="

# 直接修改 Hadoop do-component-build 添加 MAVEN_OPTS
HADOOP_DO_BUILD="$CHILD_PATH/hadoop/do-component-build"
if [ -f "$HADOOP_DO_BUILD" ]; then
  # 在 set -ex 后面添加 MAVEN_OPTS 设置
  if ! grep -q "maven.wagon.http.connectionTimeout" "$HADOOP_DO_BUILD"; then
    sed -i '/^set -ex$/a\
\
# Maven HTTP timeout settings for large dependencies (aws-java-sdk-bundle)\
# Also disable proxy for local nexus to avoid socks5 timeout issues\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.http.retryHandler.count=3"\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.http.pool=false"\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.httpconnectionManager.ttlSeconds=120"\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.http.connectionTimeout=600000"\
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.wagon.http.readTimeout=600000"\
export MAVEN_OPTS="${MAVEN_OPTS} -Dhttp.nonProxyHosts=localhost|127.0.0.1|nexus|172.20.*"\
export MAVEN_OPTS="${MAVEN_OPTS} -Dhttps.nonProxyHosts=localhost|127.0.0.1|nexus|172.20.*"\
echo "✓ Maven HTTP timeout configured: 600s (10 minutes)"' "$HADOOP_DO_BUILD"
    
    echo "✓ Maven HTTP 超时已添加到 do-component-build"
  else
    echo "✓ Maven HTTP 超时配置已存在，跳过"
  fi
else
  echo "⚠ 未找到 do-component-build，跳过 Maven 超时配置"
fi

echo "  - 连接超时: 600秒 (10分钟)"
echo "  - 读取超时: 600秒 (10分钟)"
echo "  - 重试次数: 3次"

echo "✓ Bigtop 预构建配置完成"
echo "  - 所有补丁已应用"
echo "  - Hadoop 配置: Node.js v12.22.12 + node-sass v4.13.0"
echo "  - Moment.js locale 冲突修复已添加到 do-component-build"
echo "  - Maven HTTP 超时已配置"

echo "############## PRE BUILD BIGTOP end #############"
