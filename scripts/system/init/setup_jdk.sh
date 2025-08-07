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

########### JDK_INIT start

echo "############## SETUP JDK_INIT start #############"

# ------- JDK 8 相关参数 -------
JDK8_FILE_PATH="/opt/modules/jdk-8u202-linux-x64.tar.gz"
JDK8_FILE_HOME_PATH="/opt/modules/jdk1.8.0_202"
JDK8_DOWNLOAD_URL="https://repo.huaweicloud.com/java/jdk/8u202-b08/jdk-8u202-linux-x64.tar.gz"

# ------- JDK 17 相关参数 -------
JDK17_VERSION="17.0.16_8"
JDK17_SHORT="17.0.16"
JDK17_FILENAME="OpenJDK17U-jdk_x64_linux_hotspot_${JDK17_VERSION}.tar.gz"
JDK17_DOWNLOAD_URL="https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/linux/${JDK17_FILENAME}"
JDK17_FILE_PATH="/opt/modules/${JDK17_FILENAME}"

JDK_FILE_PATH_LOCK="/data/.setup_jdk.lock"
TAR_LOCK="/data/.setup_jdk_tar.lock"
mkdir -p /data /opt/modules

# 解压缩函数
extract_tar_gz() {
    local file_path=$1
    local dest_dir=$2

    if [ -f "$TAR_LOCK" ]; then
        return
    else
        touch $TAR_LOCK
    fi

    echo "Extracting file $file_path to directory $dest_dir..."
    tar -zxvf "$file_path" -C "$dest_dir"
    if [ $? -eq 0 ]; then
        echo "File extracted successfully: $dest_dir"
    else
        echo "File extraction failed"
        exit 1
    fi

    rm -f $TAR_LOCK
}

# 检查并下载 JDK 文件
check_and_download_jdk() {
    local file_path=$1
    local download_url=$2

    if [ -f "$file_path" ]; then
        echo "JDK file exists: $file_path"
    elif [ -f "$JDK_FILE_PATH_LOCK" ]; then
        echo "Other instance downloading..."
    else
        touch $JDK_FILE_PATH_LOCK
        echo "openjdk file does not exist, downloading..."
        mkdir -p "$(dirname "$file_path")"
        curl -L -o "$file_path" "$download_url"

        if [ $? -eq 0 ]; then
            echo "openjdk download success: $file_path"
        else
            echo "openjdk download failed!!"
            rm -f $JDK_FILE_PATH_LOCK
            exit 1
        fi

        rm -f $JDK_FILE_PATH_LOCK
    fi

    while [ -f "$JDK_FILE_PATH_LOCK" ]; do
        echo "Waiting for the lock to be released..."
        sleep 1
    done

    echo "Lock released. Continuing..."
}

# 配置 JAVA_HOME
configure_java8_home() {
    # 删除旧配置
    sed -i '/^export JAVA_HOME=/d' /etc/profile
    sed -i '/JAVA_HOME\/bin/d' /etc/profile
    # 新增 JDK8 配置
    echo "export JAVA_HOME=${JDK8_FILE_HOME_PATH}" | tee -a /etc/profile
    echo 'export PATH=$PATH:$JAVA_HOME/bin' | tee -a /etc/profile
    source /etc/profile
    echo "JAVA_HOME is set to: $JAVA_HOME"
}

main() {
    # 下载并解压 JDK 8
    check_and_download_jdk "$JDK8_FILE_PATH" "$JDK8_DOWNLOAD_URL"
    [ -d "$JDK8_FILE_HOME_PATH" ] || extract_tar_gz "$JDK8_FILE_PATH" "/opt/modules"

    # 下载并解压 JDK 17（不配置环境变量）
    check_and_download_jdk "$JDK17_FILE_PATH" "$JDK17_DOWNLOAD_URL"
    # 解压JDK17到/opt/modules，如果存在则跳过
    local jdk17_home_dir=$(ls -d /opt/modules/jdk-17.0.* 2>/dev/null | head -n 1)
    [ -d "$jdk17_home_dir" ] || extract_tar_gz "$JDK17_FILE_PATH" "/opt/modules"

    configure_java8_home

    echo "当前默认 JAVA_HOME 为 JDK 8，如需切换 JDK 17，手动修改 /etc/profile 并 source 一下即可。"
}

main

########### JDK_INIT end

echo "############## SETUP JDK_INIT end #############"
