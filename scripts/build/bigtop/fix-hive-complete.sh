#!/bin/bash
# Hive 完整修复脚本 - 修复所有已知问题

echo '→ 应用 Hive 完整修复...'

# 修复 1: do-component-build 添加 Maven PATH
DO_COMPONENT_BUILD='/opt/modules/bigtop/bigtop-packages/src/common/hive/do-component-build'
if [ -f "$DO_COMPONENT_BUILD" ]; then
    # 检查是否已添加 PATH
    if ! grep -q 'export PATH=/opt/modules/apache-maven' "$DO_COMPONENT_BUILD"; then
        # 在 set -ex 后添加 PATH
        sed -i '/^set -ex$/a\\n# 添加 Maven 到 PATH\nexport PATH=/opt/modules/apache-maven-3.8.4/bin:/usr/local/bin:/usr/bin:/bin:$PATH' "$DO_COMPONENT_BUILD"
        echo '✓ do-component-build Maven PATH 已添加'
    else
        echo '✓ do-component-build Maven PATH 已存在'
    fi
fi

# 修复 2: 运行时修复 IndexCache.java（源码解压后）
HIVE_SRC='/opt/modules/bigtop/build/hive/rpm/BUILD/apache-hive-3.1.3-src'
if [ -d "$HIVE_SRC" ]; then
    cd "$HIVE_SRC"
    
    INDEX_CACHE='llap-server/src/java/org/apache/hadoop/hive/llap/shufflehandler/IndexCache.java'
    if [ -f "$INDEX_CACHE" ]; then
        if grep -q 'new TezSpillRecord(indexFileName, fs, expectedIndexOwner)' "$INDEX_CACHE"; then
            sed -i 's/new TezSpillRecord(indexFileName, fs, expectedIndexOwner)/new TezSpillRecord(indexFileName, fs.getConf(), expectedIndexOwner)/' "$INDEX_CACHE"
            echo '✓ IndexCache.java 已修复'
        else
            echo '✓ IndexCache.java 无需修复'
        fi
    fi
else
    echo '⚠ Hive 源码目录不存在（将在构建时修复）'
fi

echo '✓ Hive 修复完成'

