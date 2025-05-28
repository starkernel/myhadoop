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
# 用法: ./apply_patch.sh <PROJECT_PATH> <PATCH_FILE>
# 作用：判断补丁是否已应用，未应用则自动打补丁，并处理常见异常。
# apply_patch.sh
# 用法: /scripts/util/apply_patch.sh <PROJECT_PATH> <PATCH_FILE>
# 功能：判断补丁是否已应用，未应用则自动打补丁，支持幂等，处理新增文件等常见场景。

set -e

# 参数解析
PROJECT_PATH="$1"   # 项目目录，补丁将在此目录下应用
PATCH_FILE="$2"     # 补丁文件路径

# 参数校验
if [ -z "$PROJECT_PATH" ] || [ -z "$PATCH_FILE" ]; then
  echo "Usage: $0 <PROJECT_PATH> <PATCH_FILE>"
  exit 1
fi

echo "正在处理补丁文件：$PATCH_FILE"

# 检查补丁是否已应用（干跑反转补丁，如果能跑通说明已应用）
if patch -p1 --dry-run -R -d "$PROJECT_PATH" <"$PATCH_FILE" >/dev/null 2>&1; then
  echo "补丁：$PATCH_FILE 已经应用，跳过"
else
  # --forward：确保不会误反转补丁，幂等
  if patch -p1 --fuzz=0 --no-backup-if-mismatch --forward -d "$PROJECT_PATH" <"$PATCH_FILE"; then
    echo "补丁：$PATCH_FILE 已经成功执行"
  else
    # 特殊情况：补丁内容涉及新增文件（hunk not found）
    if grep -q "can't find file" <(patch -p1 --dry-run -d "$PROJECT_PATH" <"$PATCH_FILE" 2>&1); then
      echo "补丁：$PATCH_FILE 是新增文件，跳过"
    else
      echo "补丁：$PATCH_FILE 执行失败"
      exit 2
    fi
  fi
fi
