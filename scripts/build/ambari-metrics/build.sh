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

echo "############## PRE BUILD AMBARI-METRICS start #############"

#########################
####      PATCH       ###
#########################

patch_files=(
  "/scripts/build/ambari-metrics/patch/patch0-TAR-DOWNLOAD.diff"
)
PROJECT_PATH="/opt/modules/ambari-metrics"

apply_patch() {
  local patch_file=$1
  if patch -p1 --dry-run -R -d "$PROJECT_PATH" <"$patch_file" >/dev/null 2>&1; then
    echo "补丁 $(basename "$patch_file") 已应用，跳过"
  else
    if patch -p1 --fuzz=0 --verbose -d "$PROJECT_PATH" <"$patch_file"; then
      echo "补丁 $(basename "$patch_file") 成功执行"
    else
      echo "补丁 $(basename "$patch_file") 执行失败"
      exit 1
    fi
  fi
}

for patch_file in "${patch_files[@]}"; do
  apply_patch "$patch_file"
done

#########################
####    CHECK ENV     ###
#########################

DOWNLOAD_DIR="$PROJECT_PATH/ambari-download-tar"
RPM_PACKAGE="/data/rpm-package/ambari-metrics"
DEB_PACKAGE="/data/deb-package/ambari-metrics"

mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$RPM_PACKAGE"
mkdir -p "$DEB_PACKAGE"

# 检查是否已有 tar.gz 文件存在，如果没有则提示用户
if ! ls "$DOWNLOAD_DIR"/*.tar.gz >/dev/null 2>&1; then
  echo ""
  echo "未检测到任何 .tar.gz 环境包，您尚未准备构建依赖。"
  echo ""
  echo "请参考以下文档，获取完整的环境包下载指南和修复说明："
  echo "    https://doc.janettr.com/pages/5f4e4b32-cc79-4266-899a-83f85cf82b25/"
  echo ""
  echo "请将下载后的所有环境包文件 (.tar.gz) 放入以下目录："
  echo "    $DOWNLOAD_DIR"
  echo ""
  echo "常见缺失包包括："
  echo "    - hadoop"
  echo "    - hbase"
  echo "    - grafana"
  echo "    - phoenix"
  echo ""
  echo "注意：不建议使用国内镜像源（如清华、阿里、华为等）进行下载，"
  echo "这些镜像中部分包可能缺失或版本不一致，容易导致构建失败。"
  echo ""
  exit 1
else
  echo "✅ 检测到环境包已准备，跳过提示。"
fi

#########################
####      BUILD       ###
#########################

# ------- 自动适配 deb/rpm -------
if [ -f /etc/redhat-release ]; then
    echo "############## BUILD RPM #############"
    mvn -T 4C clean install -DskipTests -Drat.skip=true -Dbuild-rpm -X
    find "$PROJECT_PATH" -iname '*.rpm' -exec cp -rv {} "$RPM_PACKAGE" \;
elif [ -f /etc/debian_version ]; then
    echo "############## BUILD DEB #############"
    mvn -T 4C package -DskipTests -Drat.skip=true -Dbuild-deb
    find "$PROJECT_PATH" -iname '*.deb' -exec cp -rv {} "$DEB_PACKAGE" \;
else
    echo "不支持的系统类型，仅支持 RedHat/CentOS/Rocky 和 Debian/Ubuntu！"
    exit 1
fi

echo "############## PRE BUILD AMBARI-METRICS end #############"

