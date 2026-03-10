# Hive 构建状态和修复方案

## 当前状态

- Hive 正在重新构建（使用 `--rerun-tasks` 强制重建）
- 已发现并修复 2 个编译错误
- Jenkins 脚本已更新支持自动化修复

## 发现的问题

### 1. IndexCache.java 编译错误 ✅ 已修复

**错误信息**:
```
incompatible types: org.apache.hadoop.fs.FileSystem cannot be converted to org.apache.hadoop.conf.Configuration
```

**位置**: `llap-server/src/java/org/apache/hadoop/hive/llap/shufflehandler/IndexCache.java:133`

**修复**:
```java
// 原代码
tmp = new TezSpillRecord(indexFileName, fs, expectedIndexOwner);

// 修复后
tmp = new TezSpillRecord(indexFileName, fs.getConf(), expectedIndexOwner);
```

### 2. QueryTracker.java - 无需修复

**原始错误** (已解决):
```
org.apache.logging.slf4j.Log4jMarker is not public in org.apache.logging.slf4j
```

**结论**: 原代码正确，保持不变。之前尝试替换为 `Marker` 导致新错误（Marker 是抽象类）。

## 自动化修复方案

### Jenkins 脚本集成

文件: `jenkins-build-bigtop-gradle-resume.sh`

**修复方式**: 后台监控 + 自动应用补丁

```bash
# 启动后台监控 - Hive 源码解压后立即修复
docker exec centos1 bash -c '
    (
        while true; do
            HIVE_SRC="/opt/modules/bigtop/build/hive/rpm/BUILD/apache-hive-3.1.3-src"
            if [ -d "$HIVE_SRC" ]; then
                cd "$HIVE_SRC"
                
                # 修复 IndexCache.java
                INDEX_CACHE="llap-server/src/java/org/apache/hadoop/hive/llap/shufflehandler/IndexCache.java"
                if [ -f "$INDEX_CACHE" ] && grep -q "new TezSpillRecord(indexFileName, fs, expectedIndexOwner)" "$INDEX_CACHE"; then
                    sed -i "s/new TezSpillRecord(indexFileName, fs, expectedIndexOwner)/new TezSpillRecord(indexFileName, fs.getConf(), expectedIndexOwner)/" "$INDEX_CACHE"
                    echo "✓ IndexCache.java 已修复"
                fi
                
                break
            fi
            sleep 3
        done
    ) > /tmp/hive_fix.log 2>&1 &
' &
```

### 为什么使用后台监控？

1. **时机问题**: Hive 源码在 rpmbuild 阶段才解压，无法在 `build.sh` 中提前修复
2. **与 Flink 对比**:
   - Flink: 修复 POM 文件，在 `build.sh` 中通过 `fix-flink.sh` 执行
   - Hive: 修复 Java 源码，需要等源码解压后才能修复

## Gradle 增量构建问题

### 问题描述

Jenkins 脚本每次都从头构建，即使组件已完成。

### 根本原因

1. **`git checkout .` 重置文件**: `build.sh` 中的 `git checkout .` 会重置所有文件时间戳
2. **Gradle 缓存机制**: Gradle 检查 output 目录，如果有 RPM 文件（包括失败的 src.rpm）就认为任务完成
3. **失败任务不重试**: 构建失败后，Gradle 仍认为任务已执行，不会自动重试

### 解决方案

#### 方案 1: 使用 `--rerun-tasks` (当前采用)

```bash
./gradlew hive-rpm --rerun-tasks
```

强制重新执行所有任务，忽略缓存。

#### 方案 2: 清理失败的构建

```bash
# 清理特定组件
rm -rf /opt/modules/bigtop/build/hive
rm -rf /opt/modules/bigtop/output/hive

# 重新构建
./gradlew hive-rpm
```

#### 方案 3: 修改 build.sh (推荐长期方案)

移除或条件化 `git checkout .`：

```bash
# 只在首次构建时重置
if [ ! -f /tmp/bigtop_initialized ]; then
    git checkout .
    touch /tmp/bigtop_initialized
fi
```

## Jenkins 脚本优化建议

### 当前问题

1. 每次运行 `build.sh` 都会执行 `git checkout .`
2. 导致 Gradle 认为文件变化，重新构建所有组件

### 优化方案

修改 `build.sh` 或在 Jenkins 脚本中跳过 patch 应用：

```bash
# 检查是否已应用 patch
if docker exec centos1 test -f /tmp/bigtop_patched; then
    echo "✓ Patch 已应用，跳过"
else
    docker exec centos1 bash -l -c "/scripts/build/bigtop/build_bigtop_all.sh"
    docker exec centos1 touch /tmp/bigtop_patched
fi

# 直接运行 Gradle 构建
docker exec centos1 bash -c "cd /opt/modules/bigtop && ./gradlew bigtop-rpm"
```

## 监控命令

```bash
# 查看 Hive 构建日志
docker exec centos1 tail -f /tmp/hive_gradle_rebuild.log

# 查看修复日志
docker exec centos1 cat /tmp/hive_fix.log

# 检查 RPM 生成
docker exec centos1 find /opt/modules/bigtop/output/hive -name '*.rpm' -not -name '*.src.rpm'

# 检查 Gradle 任务状态
docker exec centos1 bash -c "cd /opt/modules/bigtop && ./gradlew tasks --all | grep hive"
```

---

**更新时间**: 2026-03-09 12:00
**状态**: Hive 重新构建中，预计 10-15 分钟完成
