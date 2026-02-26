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
echo "############## SETUP GITHUB_CODE_DOWNLOAD start #############"
# 目标目录和分支版本
declare -A REPOS=(
  ["/opt/modules/ambari"]="branch-2.8.0 https://ghfast.top/https://github.com/apache/ambari.git"
  ["/opt/modules/ambari3"]="branch-3.0.0 https://ghfast.top/https://github.com/apache/ambari.git"
  ["/opt/modules/ambari-metrics"]="dependabot/maven/ambari-metrics-common/com.google.guava-guava-32.0.0-jre https://ghfast.top/https://github.com/apache/ambari-metrics.git"
  ["/opt/modules/bigtop"]="release-3.2.0 https://ghfast.top/https://github.com/apache/bigtop.git"
  ["/opt/modules/ambari-infra"]="master https://ghfast.top/https://github.com/apache/ambari-infra.git"
)

# 创建目标目录的父目录
mkdir -p /opt/modules

# 遍历每个仓库配置
for TARGET_DIR in "${!REPOS[@]}"; do
  IFS=' ' read -r BRANCH_VERSION REPO_URL <<<"${REPOS[$TARGET_DIR]}"

  # 提取仓库名称
  REPO_NAME=$(basename -s .git "$REPO_URL")

  # 检查目标目录是否存在且不为空
  if [ -d "$TARGET_DIR" ] && [ "$(ls -A $TARGET_DIR 2>/dev/null)" ]; then
    echo "目录已存在且不为空: $TARGET_DIR，跳过克隆"
  else
    echo "正在处理仓库: $REPO_NAME"
    echo "正在检出仓库到 $TARGET_DIR..."
    # 使用浅克隆减少下载量，并且失败不退出
    git clone --depth 1 -b "$BRANCH_VERSION" "$REPO_URL" "$TARGET_DIR" || {
      echo "警告: 仓库检出失败: $TARGET_DIR (可能是网络问题，继续启动容器)"
      # 创建空目录标记，避免下次重复尝试
      mkdir -p "$TARGET_DIR"
    }
    
    if [ -d "$TARGET_DIR/.git" ]; then
      echo "仓库检出成功: $TARGET_DIR"
    else
      echo "警告: 仓库未完全克隆: $TARGET_DIR"
    fi
  fi
done

# 创建符号链接，解决路径不匹配问题
if [ -d "/opt/modules/ambari3" ] && [ ! -L "/opt/modules/ambari" ]; then
  echo "创建符号链接: /opt/modules/ambari -> /opt/modules/ambari3"
  ln -sf /opt/modules/ambari3 /opt/modules/ambari
fi

echo "############## SETUP GITHUB_CODE_DOWNLOAD end #############"
