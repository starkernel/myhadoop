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

echo "############## SETUP CONFIGURE_YUM_REPO start #############"

# Nexus 服务器信息
NEXUS_URL="http://localhost:8081"
USERNAME="admin"
PASSWORD="admin123"

########## CentOS 7 仓库 ##########
REPOS_CENTOS7=(
  "yum-huawei|https://repo.huaweicloud.com/centos/"
  "yum-aliyun|https://mirrors.aliyun.com/centos/"
  "yum-aliyun-epel|https://mirrors.aliyun.com/epel/"
  "yum-aliyun-mariadb|https://mirrors.aliyun.com/mariadb/"
)
GROUP_REPO_CENTOS7="yum-public"
GROUP_MEMBERS_CENTOS7=("yum-huawei" "yum-aliyun-epel" "yum-aliyun" "yum-aliyun-mariadb")

########## Rocky 8 仓库 ##########
REPOS_ROCKY8=(
  "rocky8-mirrors|https://mirrors.aliyun.com/rockylinux/"
  "rocky8-epel|https://mirrors.aliyun.com/"
)
GROUP_REPO_ROCKY8="yum-public-rocky8"
GROUP_MEMBERS_ROCKY8=("rocky8-mirrors" "rocky8-epel")

# ================= 函数定义 ===================

# 检查仓库是否存在
check_repo_exists() {
  local repo_name=$1
  local response
  response=$(curl -s -u "${USERNAME}:${PASSWORD}" -X GET "${NEXUS_URL}/service/rest/v1/repositories/${repo_name}")
  [[ $response == *"\"name\" : \"${repo_name}\""* ]]
}

# 创建代理仓库
create_proxy_repo() {
  local repo_name=$1
  local remote_url=$2
  local repo_config

  repo_config=$(
    cat <<EOF
{
  "name": "${repo_name}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "${remote_url}",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  }
}
EOF
  )

  curl -u "${USERNAME}:${PASSWORD}" -X POST "${NEXUS_URL}/service/rest/v1/repositories/yum/proxy" \
    -H "Content-Type: application/json" \
    -d "${repo_config}"
}

# 获取组仓库成员
get_group_members() {
  local repo_name=$1
  curl -s -u "${USERNAME}:${PASSWORD}" -X GET "${NEXUS_URL}/service/rest/v1/repositories/${repo_name}" | grep -oP '"memberNames" : \[\K[^\]]+' | tr -d '"' | tr ',' '\n'
}

# 创建组仓库
create_group_repo() {
  local repo_name=$1
  shift
  local members=("$@")
  local members_json=$(printf '"%s",' "${members[@]}")
  members_json="[${members_json%,}]"

  local repo_config

  repo_config=$(
    cat <<EOF
{
  "name": "${repo_name}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ${members_json}
  }
}
EOF
  )

  curl -u "${USERNAME}:${PASSWORD}" -X POST "${NEXUS_URL}/service/rest/v1/repositories/yum/group" \
    -H "Content-Type: application/json" \
    -d "${repo_config}"
}

# 更新组仓库成员
update_group_repo_members() {
  local repo_name=$1
  shift
  local new_members=("$@")
  local existing_members=()

  if check_repo_exists "${repo_name}"; then
    existing_members=($(get_group_members "${repo_name}"))
  fi

  local all_members=("${existing_members[@]}" "${new_members[@]}")
  local unique_members=($(echo "${all_members[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

  local members_json=$(printf '"%s",' "${unique_members[@]}")
  members_json="[${members_json%,}]"

  local repo_config

  repo_config=$(
    cat <<EOF
{
  "name": "${repo_name}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ${members_json}
  }
}
EOF
  )

  curl -u "${USERNAME}:${PASSWORD}" -X PUT "${NEXUS_URL}/service/rest/v1/repositories/yum/group/${repo_name}" \
    -H "Content-Type: application/json" \
    -d "${repo_config}"
}

# ================== 创建/更新 CentOS 7 仓库 ==================
for repo in "${REPOS_CENTOS7[@]}"; do
  IFS="|" read -r repo_name remote_url <<<"${repo}"
  if check_repo_exists "${repo_name}"; then
    echo "仓库 ${repo_name} 已存在。"
  else
    echo "正在创建代理仓库 ${repo_name}..."
    create_proxy_repo "${repo_name}" "${remote_url}"
  fi
done

if check_repo_exists "${GROUP_REPO_CENTOS7}"; then
  echo "组仓库 ${GROUP_REPO_CENTOS7} 已存在，正在更新成员..."
  update_group_repo_members "${GROUP_REPO_CENTOS7}" "${GROUP_MEMBERS_CENTOS7[@]}"
else
  echo "组仓库 ${GROUP_REPO_CENTOS7} 不存在，正在创建..."
  create_group_repo "${GROUP_REPO_CENTOS7}" "${GROUP_MEMBERS_CENTOS7[@]}"
fi

# ================== 创建/更新 Rocky 8 仓库 ==================
for repo in "${REPOS_ROCKY8[@]}"; do
  IFS="|" read -r repo_name remote_url <<<"${repo}"
  if check_repo_exists "${repo_name}"; then
    echo "仓库 ${repo_name} 已存在。"
  else
    echo "正在创建代理仓库 ${repo_name}..."
    create_proxy_repo "${repo_name}" "${remote_url}"
  fi
done

if check_repo_exists "${GROUP_REPO_ROCKY8}"; then
  echo "组仓库 ${GROUP_REPO_ROCKY8} 已存在，正在更新成员..."
  update_group_repo_members "${GROUP_REPO_ROCKY8}" "${GROUP_MEMBERS_ROCKY8[@]}"
else
  echo "组仓库 ${GROUP_REPO_ROCKY8} 不存在，正在创建..."
  create_group_repo "${GROUP_REPO_ROCKY8}" "${GROUP_MEMBERS_ROCKY8[@]}"
fi

echo "仓库创建成功。"


#
## =========== YUM REPO 预热（repodata、modules.yaml.xz等） ===========
#echo "############## PREHEATING YUM PROXY REPO (repodata) #############"
#
#ROCKY_VERSIONS=("8" "8.10")
#REPO_NAMES=("BaseOS" "AppStream" "extras" "epel")
#REMOTE_MIRROR="https://mirrors.aliyun.com/rockylinux"
#REMOTE_EPEL="https://mirrors.aliyun.com/epel"
#NEXUS_GROUP_PROXY="yum-public-rocky8"
#
#for ROCKY_VERSION in "${ROCKY_VERSIONS[@]}"; do
#  for repo in "${REPO_NAMES[@]}"; do
#    if [[ "$repo" == "epel" ]]; then
#      # epel 只用 "8" 这个版本目录，不存在 8.10
#      SRC_REPODATA_URL="${REMOTE_EPEL}/8/Everything/x86_64/repodata/"
#      NEXUS_REPODATA_URL="${NEXUS_URL}/repository/${NEXUS_GROUP_PROXY}/epel/8/Everything/x86_64/repodata"
#      # 如果当前不是 8，也可以选择 skip（效率最高）
#      if [[ "$ROCKY_VERSION" != "8" ]]; then
#        continue
#      fi
#    else
#      SRC_REPODATA_URL="${REMOTE_MIRROR}/${ROCKY_VERSION}/${repo}/x86_64/os/repodata/"
#      NEXUS_REPODATA_URL="${NEXUS_URL}/repository/${NEXUS_GROUP_PROXY}/${ROCKY_VERSION}/${repo}/x86_64/os/repodata"
#    fi
#
#    echo "预热仓库：$ROCKY_VERSION/$repo"
#    FILE_LIST=$(curl -s "${SRC_REPODATA_URL}" | grep -oP '(?<=href=")[^"]+\.(xml|gz|xz)')
#    if [ -z "$FILE_LIST" ]; then
#      echo "  [WARN] 路径下无 repodata：$SRC_REPODATA_URL"
#      continue
#    fi
#    for file in $FILE_LIST; do
#      echo "  拉取 $file"
#      curl -sf "${NEXUS_REPODATA_URL}/$file" -o /dev/null || echo "  [WARN] 预热失败: $file"
#    done
#  done
#done

echo "############## PREHEAT FINISH #############"


echo "############## SETUP CONFIGURE_YUM_REPO end #############"


