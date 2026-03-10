# Hive 构建成功 - 最终版本

## 构建结果

✅ **Hive 3.1.3 构建成功！**

**构建时间**: 2026-03-10 02:07-02:09  
**RPM 包数量**: 9 个  
**总大小**: 350M

## 生成的 RPM 包

已成功拷贝到 `/data/rpm-package/bigtop/hive/`:

```
hive-3.1.3-1.el7.noarch.rpm                    (276M) - 主包
hive-server2-3.1.3-1.el7.noarch.rpm           (4.9K) - HiveServer2
hive-metastore-3.1.3-1.el7.noarch.rpm         (4.8K) - Metastore
hive-hbase-3.1.3-1.el7.noarch.rpm             (116K) - HBase 集成
hive-jdbc-3.1.3-1.el7.noarch.rpm              (71M)  - JDBC 驱动
hive-hcatalog-3.1.3-1.el7.noarch.rpm          (494K) - HCatalog
hive-webhcat-3.1.3-1.el7.noarch.rpm           (3.0M) - WebHCat
hive-hcatalog-server-3.1.3-1.el7.noarch.rpm   (4.8K) - HCatalog Server
hive-webhcat-server-3.1.3-1.el7.noarch.rpm    (4.7K) - WebHCat Server
```

## 修复方案总结

### 问题 1: IndexCache.java - FileSystem 类型错误

**错误**: `incompatible types: org.apache.hadoop.fs.FileSystem cannot be converted to org.apache.hadoop.conf.Configuration`

**解决方案**: 使用 Bigtop 官方 patch1-HIVE-23190.diff
- 该 patch 已包含在 Bigtop 中并自动应用
- 无需额外修复

**修复内容**:
```java
// 添加 FileSystem 字段
private FileSystem fs;

// 初始化方法
private void initLocalFs() {
    try {
        this.fs = FileSystem.getLocal(conf).getRaw();
    } catch (IOException e) {
        throw new RuntimeException(e);
    }
}

// 使用 fs 而不是 conf
tmp = new TezSpillRecord(indexFileName, fs, expectedIndexOwner);
```

### 问题 2: QueryTracker.java - Log4jMarker 访问权限

**错误**: `org.apache.logging.slf4j.Log4jMarker is not public in org.apache.logging.slf4j; cannot be accessed from outside package`

**解决方案**: 在 `do-component-build` 脚本中添加修复代码

**修复内容**:
```bash
# 替换 import 语句
sed -i 's/import org.apache.logging.slf4j.Log4jMarker;/import org.slf4j.MarkerFactory;/' "$QUERY_TRACKER"

# 替换 Marker 实例化
sed -i 's/new Log4jMarker(new Log4jQueryCompleteMarker())/MarkerFactory.getMarker("QUERY_COMPLETE")/' "$QUERY_TRACKER"
```

**原理**: 
- `Log4jMarker` 在新版本 log4j 中不可访问
- 使用 SLF4J 标准的 `MarkerFactory.getMarker()` 替代
- 保持日志功能不变

## 修复文件位置

**do-component-build 脚本**: `/opt/modules/bigtop/bigtop-packages/src/common/hive/do-component-build`

修复代码在 Maven 构建命令之前执行：
```bash
# === Hive 编译错误修复 ===
echo '→ 修复 Hive Log4j 兼容性问题...'

# 修复 QueryTracker.java - Log4jMarker 访问权限问题
# 使用 SLF4J 的 MarkerFactory 替代 Log4jMarker
QUERY_TRACKER='llap-server/src/java/org/apache/hadoop/hive/llap/daemon/impl/QueryTracker.java'
if [ -f "$QUERY_TRACKER" ]; then
    sed -i 's/import org.apache.logging.slf4j.Log4jMarker;/import org.slf4j.MarkerFactory;/' "$QUERY_TRACKER"
    sed -i 's/new Log4jMarker(new Log4jQueryCompleteMarker())/MarkerFactory.getMarker("QUERY_COMPLETE")/' "$QUERY_TRACKER"
    echo '✓ QueryTracker.java 已修复 (使用 MarkerFactory)'
else
    echo '⚠ QueryTracker.java 不存在'
fi

echo '✓ Hive 修复完成'
```

## 构建流程

```
Gradle 任务: hive-rpm
  ↓
rpmbuild 解压 Hive 源码
  ↓
应用 Bigtop patches (包括 patch1-HIVE-23190.diff)
  ↓
执行 do-component-build 脚本
  ↓
【自动修复】QueryTracker.java (Log4jMarker -> MarkerFactory)
  ↓
Maven 构建 (mvn install -DskipTests)
  ↓
生成 Hive RPM 包 (9 个)
  ↓
拷贝到 /data/rpm-package/bigtop/hive/
```

## 关键经验教训

### 1. 不要重复修复已有 patch 的问题

- Bigtop 已经包含了 IndexCache 的官方修复 (patch1-HIVE-23190.diff)
- 我们的初始修复尝试反而破坏了 patch 的效果
- 应该先检查现有 patches，避免重复劳动

### 2. 理解修复的根本原因

- IndexCache 问题：TezSpillRecord 构造函数需要 FileSystem 对象，不是 Configuration
- QueryTracker 问题：Log4jMarker 类访问权限变更，需要使用标准 SLF4J API

### 3. 修复时机很重要

- IndexCache: patch 在源码解压后自动应用
- QueryTracker: 需要在 do-component-build 中手动修复（因为没有官方 patch）

### 4. 验证修复效果

- 检查修复代码是否执行：查看构建日志
- 检查修复是否生效：查看编译错误是否消失
- 检查是否引入新问题：确保修复后代码可以编译通过

## 与 Flink 修复的对比

| 特性 | Flink 修复 | Hive 修复 |
|------|-----------|----------|
| 修复方式 | 独立脚本 `fix-flink.sh` | 嵌入 `do-component-build` |
| 调用时机 | `build.sh` 中 `git checkout` 后 | rpmbuild 解压源码后 |
| 修复对象 | POM 文件 (XML) | Java 源码 |
| 修复内容 | Nexus 仓库配置 | Log4j 兼容性 |
| 官方支持 | 无官方 patch | 部分有官方 patch (IndexCache) |

## 下一步

现在 Hive 已经成功构建，可以：

1. 继续构建其他 Bigtop 组件
2. 运行完整的 Jenkins 构建脚本
3. 测试 Hive RPM 包的安装和功能

## 相关文档

- `HIVE_BUILD_STATUS.md` - 构建状态和问题分析
- `HIVE_LOG4J_FIX.md` - Log4j 兼容性问题详解
- `HIVE_BUILD_READY.md` - 构建准备文档
- `jenkins-build-bigtop-gradle-resume.sh` - Jenkins 自动构建脚本

---

**构建完成时间**: 2026-03-10 02:11  
**状态**: ✅ 成功  
**RPM 包位置**: `/data/rpm-package/bigtop/hive/`
