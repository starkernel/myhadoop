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

echo "############## PRE BUILD_AMBARI_ALL start #############"

PROJECT_PATH="/opt/modules/ambari3"   # 你的目标项目路径
PATCH_SCRIPT="/scripts/util/apply_patch.sh"  # 工具脚本路径
DEB_PACKAGE="/data/deb-package/ambari3" # 目标路径

mkdir -p $DEB_PACKAGE


cd "$PROJECT_PATH"
rm -rf "$PROJECT_PATH"/* && git checkout .

patch_files=(
  "/scripts/build/ambari3-ub2204/patch2_0_0/patch0-COMPONENT-VERSION-UPGRADE.diff"
  "/scripts/build/ambari3-ub2204/patch2_0_0/patch1-COMPONENT-RPM-BAN.diff"
  # 后续可继续添加补丁文件路径
)

for patch_file in "${patch_files[@]}"; do
  "$PATCH_SCRIPT" "$PROJECT_PATH" "$patch_file"
done


# 使用jdk 17
export JAVA_HOME=/opt/modules/jdk-17.0.15+6
export PATH=$JAVA_HOME/bin:$PATH

java -version

# Maven 构建并打 deb 包
mvn -T 16 -B clean install jdeb:jdeb \
  -Drat.skip=true \
  -Dcheckstyle.skip=true \
  -DskipTests \
  -Dspotbugs.skip=true \
  -Preplaceurl

# 只收集 .deb 包
find "$PROJECT_PATH" -iname '*.deb' -exec cp -rv {} "$DEB_PACKAGE" \;

echo "############## PRE BUILD_AMBARI_ALL end #############"
