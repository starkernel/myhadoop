#!/bin/bash
# 修复 Nexus 中的 MariaDB 仓库配置

set -e

NEXUS_URL="http://localhost:8081"
USERNAME="admin"
PASSWORD="admin123"

echo "========================================="
echo "修复 MariaDB 仓库配置"
echo "========================================="

# 检查 Nexus 是否运行
if ! curl -sf "${NEXUS_URL}" > /dev/null; then
    echo "错误: Nexus 未运行或无法访问"
    exit 1
fi

# 检查 yum-aliyun-mariadb 仓库是否存在
echo "→ 检查 MariaDB 代理仓库..."
REPO_EXISTS=$(curl -s -u "${USERNAME}:${PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories" | \
    grep -c '"name" : "yum-aliyun-mariadb"' || echo "0")

if [ "$REPO_EXISTS" -gt 0 ]; then
    echo "✓ yum-aliyun-mariadb 仓库已存在"
    
    # 获取当前配置
    echo "→ 检查仓库配置..."
    CURRENT_URL=$(curl -s -u "${USERNAME}:${PASSWORD}" \
        "${NEXUS_URL}/service/rest/v1/repositories/yum-aliyun-mariadb" | \
        grep -oP '"remoteUrl" : "\K[^"]+' || echo "")
    
    echo "  当前远程 URL: $CURRENT_URL"
    
    # 如果 URL 不正确，更新它
    CORRECT_URL="https://mirrors.aliyun.com/mariadb/yum/10.11/centos7-amd64/"
    
    if [ "$CURRENT_URL" != "$CORRECT_URL" ]; then
        echo "→ 更新 MariaDB 仓库 URL..."
        
        # 删除旧仓库
        curl -s -u "${USERNAME}:${PASSWORD}" -X DELETE \
            "${NEXUS_URL}/service/rest/v1/repositories/yum-aliyun-mariadb"
        
        echo "  旧仓库已删除"
        sleep 2
        
        # 创建新仓库
        curl -s -u "${USERNAME}:${PASSWORD}" -X POST \
            "${NEXUS_URL}/service/rest/v1/repositories/yum/proxy" \
            -H "Content-Type: application/json" \
            -d '{
              "name": "yum-aliyun-mariadb",
              "online": true,
              "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": true
              },
              "proxy": {
                "remoteUrl": "'"${CORRECT_URL}"'",
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
            }'
        
        echo "✓ MariaDB 仓库已更新"
    else
        echo "✓ MariaDB 仓库 URL 正确"
    fi
else
    echo "→ 创建 MariaDB 代理仓库..."
    
    curl -s -u "${USERNAME}:${PASSWORD}" -X POST \
        "${NEXUS_URL}/service/rest/v1/repositories/yum/proxy" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "yum-aliyun-mariadb",
          "online": true,
          "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true
          },
          "proxy": {
            "remoteUrl": "https://mirrors.aliyun.com/mariadb/yum/10.11/centos7-amd64/",
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
        }'
    
    echo "✓ MariaDB 仓库已创建"
fi

# 确保 MariaDB 仓库在 yum-public 组中
echo ""
echo "→ 检查 yum-public 组仓库..."
GROUP_MEMBERS=$(curl -s -u "${USERNAME}:${PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories/yum-public" | \
    grep -oP '"memberNames" : \[\K[^\]]+' | tr -d '"' | tr ',' '\n')

if echo "$GROUP_MEMBERS" | grep -q "yum-aliyun-mariadb"; then
    echo "✓ MariaDB 仓库已在 yum-public 组中"
else
    echo "→ 将 MariaDB 仓库添加到 yum-public 组..."
    
    # 获取现有成员并添加 MariaDB
    MEMBERS_ARRAY=$(echo "$GROUP_MEMBERS" | sed 's/^/"/' | sed 's/$/"/' | paste -sd,)
    if [ -n "$MEMBERS_ARRAY" ]; then
        MEMBERS_ARRAY="${MEMBERS_ARRAY},\"yum-aliyun-mariadb\""
    else
        MEMBERS_ARRAY="\"yum-aliyun-mariadb\""
    fi
    
    curl -s -u "${USERNAME}:${PASSWORD}" -X PUT \
        "${NEXUS_URL}/service/rest/v1/repositories/yum/group/yum-public" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "yum-public",
          "online": true,
          "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true
          },
          "group": {
            "memberNames": ['"${MEMBERS_ARRAY}"']
          }
        }'
    
    echo "✓ MariaDB 仓库已添加到 yum-public 组"
fi

echo ""
echo "========================================="
echo "配置完成！"
echo "========================================="
echo ""
echo "MariaDB 仓库信息:"
echo "  - 仓库名称: yum-aliyun-mariadb"
echo "  - 远程 URL: https://mirrors.aliyun.com/mariadb/yum/10.11/centos7-amd64/"
echo "  - Nexus URL: ${NEXUS_URL}/repository/yum-public/yum/10.11.10/centos7-amd64/"
echo ""
echo "测试访问:"
echo "  curl -I ${NEXUS_URL}/repository/yum-public/yum/10.11.10/centos7-amd64/repodata/repomd.xml"
echo ""
