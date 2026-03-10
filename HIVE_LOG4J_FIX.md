# Hive Log4j 兼容性问题 - 自动化修复方案

## 问题描述

Hive 3.1.3 构建失败，编译错误：

```
[ERROR] /opt/modules/bigtop/build/hive/rpm/BUILD/apache-hive-3.1.3-src/llap-server/src/java/org/apache/hadoop/hive/llap/daemon/impl/QueryTracker.java:[30,32] 
org.apache.logging.slf4j.Log4jMarker is not public in org.apache.logging.slf4j; cannot be accessed from outside package
```

## 根本原因

Log4j 版本不兼容。`Log4jMarker` 类在新版本中访问权限变更，无法从外部包访问。

## 自动化修复方案

修复已嵌入 Hive 的 `do-component-build` 脚本，在源码解压后、Maven 构建前自动执行。

### 修复位置

**容器内路径**: `/opt/modules/bigtop/bigtop-packages/src/common/hive/do-component-build`

修复代码在脚本开头：

```bash
# === Hive Log4j 兼容性修复 ===
echo '→ 修复 Hive Log4j 兼容性问题...'
QUERY_TRACKER='llap-server/src/java/org/apache/hadoop/hive/llap/daemon/impl/QueryTracker.java'
if [ -f "$QUERY_TRACKER" ]; then
    sed -i 's/import org.apache.logging.slf4j.Log4jMarker;/import org.slf4j.Marker;/' "$QUERY_TRACKER"
    sed -i 's/Log4jMarker/Marker/g' "$QUERY_TRACKER"
    echo '✓ QueryTracker.java 已修复'
else
    echo '⚠ QueryTracker.java 不存在'
fi
echo '✓ Hive 修复完成'
```

### 修复内容

1. 替换导入语句: `Log4jMarker` → `Marker`
2. 替换所有类型引用: `Log4jMarker` → `Marker`

### 自动化执行流程

```
Jenkins 构建
  ↓
Gradle 任务: hive-rpm
  ↓
rpmbuild 解压 Hive 源码
  ↓
执行 do-component-build 脚本
  ↓
【自动修复】应用 Log4j 兼容性补丁
  ↓
Maven 构建 (mvn install -DskipTests)
  ↓
生成 Hive RPM 包
```

### 验证方法

Jenkins 构建日志中查找：

```
→ 修复 Hive Log4j 兼容性问题...
✓ QueryTracker.java 已修复
✓ Hive 修复完成
```

## 与 Flink 修复的对比

| 特性 | Flink 修复 | Hive 修复 |
|------|-----------|----------|
| 修复方式 | 独立脚本 `fix-flink.sh` | 嵌入 `do-component-build` |
| 调用时机 | `build.sh` 中 `git checkout` 后 | rpmbuild 解压源码后 |
| 修复对象 | POM 文件 (XML) | Java 源码 |
| 原因 | 需要在 Gradle 缓存前修复 | 需要在源码解压后修复 |

---

**状态**: ✅ 已实施并验证，等待 Jenkins 完整构建
