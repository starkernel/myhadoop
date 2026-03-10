# Hive 构建准备完成

## 当前状态

✅ **Hive 构建已准备就绪，可以启动 Jenkins 自动构建**

## 已完成的准备工作

### 1. 修复代码已集成到 do-component-build 脚本

**位置**: `/opt/modules/bigtop/bigtop-packages/src/common/hive/do-component-build`

**修复内容**:
```bash
# === Hive 编译错误修复 ===

# 修复 1: IndexCache.java - FileSystem 类型错误
# 将 new TezSpillRecord(indexFileName, fs, expectedIndexOwner)
# 改为 new TezSpillRecord(indexFileName, fs.getConf(), expectedIndexOwner)

# 修复 2: QueryTracker.java - Log4jMarker 访问权限问题
# 将 import org.apache.logging.slf4j.Log4jMarker
# 改为 import org.slf4j.Marker
# 并替换所有 Log4jMarker 为 Marker
```

**执行时机**: 在 Maven 构建之前自动执行

### 2. Jenkins 脚本已优化

**文件**: `jenkins-build-bigtop-gradle-resume.sh`

**改进**:
- 移除了后台监控方式（不再需要）
- 修复代码现在直接在 do-component-build 中执行
- 更清晰的日志输出

### 3. Hive 构建已清理

- ✅ 清理了 `/opt/modules/bigtop/build/hive`
- ✅ 清理了 `/opt/modules/bigtop/output/hive`
- ✅ 清理了 `/data/rpm-package/bigtop/hive`

## 启动构建的方式

### 方式 1: 测试 Hive 单独构建（推荐先测试）

```bash
./test-hive-build.sh
```

这会单独构建 Hive，验证修复是否生效。预计耗时 10-15 分钟。

### 方式 2: 启动完整 Jenkins 构建

```bash
./jenkins-build-bigtop-gradle-resume.sh
```

这会构建所有组件（Ambari + Bigtop + Ambari Infra + Ambari Metrics）。

## 构建流程说明

```
Jenkins 脚本启动
  ↓
Gradle 任务: hive-rpm
  ↓
rpmbuild 解压 Hive 源码
  ↓
执行 do-component-build 脚本
  ↓
【自动修复】两个编译错误：
  1. IndexCache.java (fs -> fs.getConf())
  2. QueryTracker.java (Log4jMarker -> Marker)
  ↓
Maven 构建 (mvn install -DskipTests)
  ↓
生成 Hive RPM 包
  ↓
复制到 /data/rpm-package/bigtop/hive
```

## 预期结果

构建成功后，应该生成以下 RPM 包：

```
/data/rpm-package/bigtop/hive/
  ├── hive-3.1.3-1.el7.noarch.rpm
  ├── hive-hbase-3.1.3-1.el7.noarch.rpm
  ├── hive-hcatalog-3.1.3-1.el7.noarch.rpm
  ├── hive-jdbc-3.1.3-1.el7.noarch.rpm
  ├── hive-metastore-3.1.3-1.el7.noarch.rpm
  ├── hive-server2-3.1.3-1.el7.noarch.rpm
  └── hive-webhcat-3.1.3-1.el7.noarch.rpm
```

## 监控命令

### 查看构建进度
```bash
# 查看 Gradle 日志
docker exec centos1 tail -f /opt/modules/bigtop/gradle_build.log

# 查看 Hive 测试日志
docker exec centos1 tail -f /opt/modules/bigtop/hive_test.log
```

### 检查修复是否应用
```bash
docker exec centos1 bash -c "
    HIVE_SRC='/opt/modules/bigtop/build/hive/rpm/BUILD/apache-hive-3.1.3-src'
    INDEX_CACHE=\"\$HIVE_SRC/llap-server/src/java/org/apache/hadoop/hive/llap/shufflehandler/IndexCache.java\"
    if [ -f \"\$INDEX_CACHE\" ]; then
        if grep -q 'fs.getConf()' \"\$INDEX_CACHE\"; then
            echo '✓ IndexCache.java 已修复'
        else
            echo '✗ IndexCache.java 未修复'
        fi
    fi
"
```

### 检查 RPM 生成
```bash
docker exec centos1 find /data/rpm-package/bigtop/hive -name '*.rpm' -not -name '*.src.rpm'
```

## 与 Flink 修复的对比

| 特性 | Flink 修复 | Hive 修复 |
|------|-----------|----------|
| 修复方式 | 独立脚本 `fix-flink.sh` | 嵌入 `do-component-build` |
| 调用时机 | `build.sh` 中 `git checkout` 后 | rpmbuild 解压源码后 |
| 修复对象 | POM 文件 (XML) | Java 源码 |
| 修复内容 | Nexus 仓库配置 | 类型转换错误 |

## 故障排查

### 如果构建失败

1. 查看详细日志:
   ```bash
   docker exec centos1 cat /opt/modules/bigtop/hive_test.log | less
   ```

2. 检查修复是否应用:
   ```bash
   docker exec centos1 grep -A 5 "Hive 编译错误修复" /opt/modules/bigtop/bigtop-packages/src/common/hive/do-component-build
   ```

3. 手动验证修复:
   ```bash
   docker exec centos1 bash -c "
       cd /opt/modules/bigtop/build/hive/rpm/BUILD/apache-hive-3.1.3-src
       grep 'fs.getConf()' llap-server/src/java/org/apache/hadoop/hive/llap/shufflehandler/IndexCache.java
   "
   ```

### 如果需要重新构建

```bash
# 清理 Hive 构建
docker exec centos1 bash -c "
    rm -rf /opt/modules/bigtop/build/hive
    rm -rf /opt/modules/bigtop/output/hive
    rm -rf /data/rpm-package/bigtop/hive
"

# 重新构建
./test-hive-build.sh
```

## 下一步

1. **建议**: 先运行 `./test-hive-build.sh` 测试 Hive 单独构建
2. 如果测试成功，运行 `./jenkins-build-bigtop-gradle-resume.sh` 进行完整构建
3. 构建完成后，检查所有组件的 RPM 包是否生成

---

**准备完成时间**: 2026-03-10
**状态**: ✅ 就绪，可以启动构建
