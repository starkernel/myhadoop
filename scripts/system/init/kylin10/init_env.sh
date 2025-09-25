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
# Author: JaneTTR (Kylin V10 only)

set -ex
echo "############## INIT KYLIN V10 start #############"
FLAG_FILE="/var/lib/init/.lock"
mkdir -p /var/lib/init

# ========== Kylin V10 repo 模板（通过 Nexus 组仓库） ==========
# 假设 Nexus 已创建组仓库：yum-public-kylinv10
# 组仓库成员至少包含：kylin-v10-sp3 -> https://update.cs2c.com.cn/NS/V10/V10SP3/
write_repo_kylin_v10() {
  cat >/etc/yum.repos.d/kylin-v10.repo <<EOF
[kylin-base]
name=Kylin V10 SP3 - Base (via Nexus)
baseurl=http://$1:8081/repository/yum-public-kylinv10/os/adv/lic/base/\$basearch/
enabled=1
gpgcheck=0

[kylin-updates]
name=Kylin V10 SP3 - Updates (via Nexus)
baseurl=http://$1:8081/repository/yum-public-kylinv10/os/adv/lic/updates/\$basearch/
enabled=1
gpgcheck=0
EOF
}

# ========== 修补 /etc/profile（使其对 set -e 友好，并增加 hostname 多级回退） ==========
install_hostname_fallback() {
  set -e
  local backup="/etc/profile.bak.$(date +%F_%H%M%S)"
  cp -a /etc/profile "$backup" || true

  awk '
  BEGIN{
    added_guard_start=0; replaced_host=0; replaced_hist=0; guarded_pd=0
  }
  NR==1 {
    # 在文件最开头插入 errexit 保护（避免被 set -e 的调用者“连坐”）
    print "__PROFILE_OLD_OPTS__=\"$-\""
    print "set +e"
    added_guard_start=1
  }
  # 将直接使用 hostnamectl 的行替换为“多级回退 + 不因失败退出”
  /hostnamectl[[:space:]].*--transient/ && replaced_host==0 {
    print "HOSTNAME=\"\""
    print "if command -v hostnamectl >/dev/null 2>&1; then"
    print "  HOSTNAME=\"$(hostnamectl --transient 2>/dev/null || true)\""
    print "fi"
    print "[ -z \"$HOSTNAME\" ] && HOSTNAME=\"$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || uname -n)\""
    print "export HOSTNAME"
    replaced_host=1
    next
  }
  # 将 HISTSIZE=1000 改为 export 形式（保留已有 HISTSIZE 优先）
  /^[[:space:]]*HISTSIZE=1000[[:space:]]*$/ && replaced_hist==0 {
    print "export HISTSIZE=\"${HISTSIZE:-1000}\""
    replaced_hist=1
    next
  }
  # 给 /etc/profile.d/*.sh 循环加保护，避免某个脚本非零导致整体退出
  /^for[[:space:]]+i[[:space:]]+in[[:space:]]+\/etc\/profile\.d\/\*\.sh[[:space:]]+\/etc\/profile\.d\/sh\.local[[:space:]]*;/ && guarded_pd==0 {
    print "## begin: guard profile.d block from errexit"
    print "__PD_OLD_OPTS__=\"$-\""
    print "set +e"
    guarded_pd=1
    print
    next
  }
  # 循环结束处恢复调用者 errexit 状态
  /^[[:space:]]*done[[:space:]]*$/ && guarded_pd==1 {
    print "## end: guard profile.d block"
    print "[[ \"$__PD_OLD_OPTS__\" == *\"e\"* ]] && set -e || true"
    print "unset __PD_OLD_OPTS__"
    print
    next
  }

  { print }

  END{
    # 如未匹配到 hostnamectl 行，追加一段安全的 HOSTNAME 设定
    if (replaced_host==0) {
      print ""
      print "# (auto-added) robust HOSTNAME fallback"
      print "HOSTNAME=\"\""
      print "if command -v hostnamectl >/dev/null 2>&1; then"
      print "  HOSTNAME=\"$(hostnamectl --transient 2>/dev/null || true)\""
      print "fi"
      print "[ -z \"$HOSTNAME\" ] && HOSTNAME=\"$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || uname -n)\""
      print "export HOSTNAME"
    }
    # 如未匹配到 HISTSIZE，追加默认导出
    if (replaced_hist==0) {
      print "export HISTSIZE=\"${HISTSIZE:-1000}\""
    }
    # 文件末尾恢复调用者的 -e 状态
    print "[[ \"$__PROFILE_OLD_OPTS__\" == *\"e\"* ]] && set -e || true"
    print "unset __PROFILE_OLD_OPTS__"
  }
  ' "$backup" > /etc/profile.new

  mv /etc/profile.new /etc/profile
  echo "Patched /etc/profile (backup at $backup)"
}


# ========== Kylin V10 初始化 ==========
init_kylin_v10() {
  rm -rf /etc/yum.repos.d/*.repo.rpmnew /etc/yum.repos.d/ambari-bigtop* || true
  (dnf clean all || true) && (dnf clean packages || true)
  (yum clean all || true)

  echo "执行 Kylin V10 初始化脚本"

  # 优先 dnf，找不到回退 yum
  PKG_INSTALL="dnf -y install"
  command -v dnf >/dev/null 2>&1 || PKG_INSTALL="yum -y install"

  # 常用工具 & 运行时
  ${PKG_INSTALL} \
    curl wget vim tar unzip which sudo \
    net-tools iproute less lsof \
    openssh-server \
    iputils \
    passwd \
    || true

  # 开发工具链
  ${PKG_INSTALL} \
    gcc gcc-c++ make cmake autoconf automake libtool m4 autoconf-archive pkgconf \
    rpm-build rsync \
    || true

  # 常见库 & 头文件（Kylin 源中存在）
  ${PKG_INSTALL} \
    zlib-devel libzstd-devel \
    bzip2-devel snappy-devel libzip-devel \
    libtirpc-devel krb5-devel openssl-devel libxml2-devel \
    protobuf protobuf-devel protobuf-compiler \
    lzo-devel \
    fuse fuse-devel \
    cppunit-devel \
    asciidoc docbook2X xmlto \
    lsb-core \
    || true
}

# ========== 主流程（仅 Kylin V10） ==========
rm_init_repos() {
  NEXUS_IP=$(cat /scripts/system/before/nexus/.lock)
  echo "读取 nexus 服务器地址：$NEXUS_IP"

  # 统一小写，避免大小写导致匹配失败
  OS_ID=$(grep -oP '^ID="?([^"]+)"?' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
  OS_VERSION_ID_RAW=$(grep -oP '^VERSION_ID="?([^"]+)"?' /etc/os-release | cut -d= -f2 | tr -d '"')
  OS_VERSION_ID=$(echo "${OS_VERSION_ID_RAW}" | tr '[:upper:]' '[:lower:]')
  PRETTY=$(grep -oP '^PRETTY_NAME="?([^"]+)"?' /etc/os-release | cut -d= -f2- | tr -d '"')
  PRETTY_LC=$(echo "$PRETTY" | tr '[:upper:]' '[:lower:]')

  echo "调试: OS_ID=${OS_ID}, VERSION_ID=${OS_VERSION_ID_RAW}, PRETTY_NAME=${PRETTY}"

  # 判断是否为 Kylin V10：ID 必须为 kylin，且版本包含 v10/10
  IS_KYLIN_V10=0
  if [[ "$OS_ID" == "kylin" ]]; then
    if [[ "$OS_VERSION_ID" =~ ^v?10($|[^0-9]) ]] || echo "$PRETTY_LC" | grep -q 'v10'; then
      IS_KYLIN_V10=1
    fi
  fi

  if [[ $IS_KYLIN_V10 -eq 1 ]]; then
    write_repo_kylin_v10 "$NEXUS_IP"
    echo "repo 文件已写入，正在初始化 Kylin V10 ..."
    init_kylin_v10
    install_hostname_fallback
  else
    echo "当前系统不是 Kylin V10 (检测到: OS_ID=${OS_ID}, VERSION_ID=${OS_VERSION_ID_RAW}). 脚本仅支持 Kylin V10。" >&2
    exit 1
  fi
}

rm_init_repos

# ========== 首次初始化的一次性操作 ==========
if [ ! -f "$FLAG_FILE" ]; then
  echo 'root:root' | chpasswd || true
  ssh-keygen -A || true

  # 确保 sshd_config 允许 root 登录
  if [ ! -f "/etc/ssh/sshd_config" ]; then
    touch /etc/ssh/sshd_config
  fi
  grep -q '^PermitRootLogin' /etc/ssh/sshd_config \
    && sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

  # 全局 alias 配置（带 color）
  grep -qxF "alias ll='ls -alF --color=auto'" /etc/profile || echo "alias ll='ls -alF --color=auto'" >> /etc/profile
  grep -qxF "alias ls='ls --color=auto'" /etc/profile   || echo "alias ls='ls --color=auto'"   >> /etc/profile
  grep -qxF "source /etc/profile" /root/.bashrc         || echo "source /etc/profile"          >> /etc/profile

  touch "$FLAG_FILE"
else
  echo "Kylin V10 已经完成初始化"
fi

echo "############## INIT KYLIN V10 end #############"
