# ✅ Flink 构建最终成功报告

## 构建结果

**时间**: 2026-03-08  
**状态**: ✅ 成功  
**耗时**: 约 3 小时（包含 Hadoop）

---

## 生成的 RPM 包

### Flink RPM 包（3个）

1. **flink_3_2_0-1.17.2-1.el7.noarch.rpm** (186MB)
   - 主包，包含 Flink 核心组件
   
2. **flink_3_2_0-jobmanager-1.17.2-1.el7.noarch.rpm** (4.6KB)
   - JobManager 服务包
   
3. **flink_3_2_0-taskmanager-1.17.2-1.el7.noarch.rpm** (4.6KB)
   - TaskManager 服务包

**位置**: `/opt/modules/bigtop/output/flink/noarch/`

---

## 最终解决方案

### 问题根源

Flink 构建失败的根本原因：
1. **测试 assembly 错误**: 使用 `-DskipTests` 导致 maven-assembly-plugin 找不到测试类
2. **Maven 命令找不到**: rpmbuild 环境中 PATH 不包含 Maven
3. **Git 自动恢复**: 构建脚本中的 `git checkout .` 会恢复所有修改

### 最终方案

#### 1. 创建修复脚本 `/scripts/build/bigtop/fix-flink.sh`

```bash
#!/bin/bash
echo '→ 应用 Flink 构建修复...'

cat > /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build << 'EOFSCRIPT'
#!/bin/bash
set -ex
export PATH=/opt/modules/apache-maven-3.8.4/bin:/usr/local/bin:/usr/bin:/bin:$PATH

# === Flink POM 修复 ===
echo '→ 修复 Flink POM 文件...'
[ -f 'flink-clients/pom.xml' ] && sed -i 's|<phase>process-test-classes</phase>|<phase>none</phase>|g' flink-clients/pom.xml && echo '✓ flink-clients 已修复'
[ -f 'flink-python/pom.xml' ] && sed -i '/<id>build-test-jars<\/id>/,/<\/execution>/ s|<phase>package</phase>|<phase>none</phase>|' flink-python/pom.xml && echo '✓ flink-python 已修复'
echo '✓ POM 修复完成'

export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError"
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true -Dskip.npm=true"

. `dirname $0`/bigtop.bom
[ $HOSTTYPE = 'powerpc64le' ] && sed -i 's|<nodeVersion>v10.9.0</nodeVersion>|<nodeVersion>v12.22.1</nodeVersion>|' flink-runtime-web/pom.xml

git_path="$(cd $(dirname $0)/../../../.. && pwd)"
cmd_from="cd ../.. && husky install flink-runtime-web/web-dashboard/.husky"
repl_from=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$cmd_from")
if [[ "$0" == *rpm* ]]; then
  package_json_path="build/flink/rpm/BUILD/flink-$FLINK_VERSION/flink-runtime-web/web-dashboard"
  cmd_to="cd $git_path && husky install $package_json_path/.husky"
  repl_to=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$cmd_to")
elif [[ "$0" == *debian* ]]; then
  package_json_path="output/flink/flink-$FLINK_VERSION/flink-runtime-web/web-dashboard"
  cmd_to="cd $git_path && husky install $package_json_path/.husky"
  repl_to=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$cmd_to")
fi
sed -i "s/$repl_from/$repl_to/" flink-runtime-web/web-dashboard/package.json

mvn -q install $FLINK_BUILD_OPTS -Drat.skip=true -Dmaven.test.skip=true -Dhadoop.version=$HADOOP_VERSION "$@"
cd flink-dist
mvn -q install $FLINK_BUILD_OPTS -Drat.skip=true -Dmaven.test.skip=true -Dhadoop.version=$HADOOP_VERSION "$@"
EOFSCRIPT

chmod +x /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build
echo '✓ Flink 修复已应用'
```

#### 2. 修改 `/scripts/build/bigtop/build.sh`

在 `git checkout .` 后添加：
```bash
git checkout .
bash /scripts/build/bigtop/fix-flink.sh
```

#### 3. 禁用冲突的补丁

将 `/scripts/build/bigtop/patch/patch2-FLINK-FIXED.diff` 改为空补丁：
```diff
diff --git a/bigtop-packages/src/common/flink/.gitkeep b/bigtop-packages/src/common/flink/.gitkeep
new file mode 100644
index 00000000..e69de29b
```

---

## 关键修复点

### 1. POM 文件修复

**flink-clients/pom.xml**:
```xml
<!-- 修改前 -->
<phase>process-test-classes</phase>

<!-- 修改后 -->
<phase>none</phase>
```

**flink-python/pom.xml**:
```xml
<!-- 修改前 -->
<id>build-test-jars</id>
...
<phase>package</phase>

<!-- 修改后 -->
<id>build-test-jars</id>
...
<phase>none</phase>
```

### 2. Maven 参数

- ✅ 使用 `-Dmaven.test.skip=true`（完全跳过测试）
- ❌ 不使用 `-DskipTests`（会编译测试但不运行）

### 3. PATH 设置

```bash
export PATH=/opt/modules/apache-maven-3.8.4/bin:/usr/local/bin:/usr/bin:/bin:$PATH
```

---

## 构建流程

```
Jenkins 启动
    ↓
git checkout . (恢复所有文件)
    ↓
fix-flink.sh (重新应用修复)
    ↓
Gradle 构建
    ↓
rpmbuild 执行
    ↓
do-component-build 运行
    ├─ 修复 POM 文件
    ├─ 设置 PATH
    └─ Maven 构建
    ↓
✓ Flink RPM 生成
```

---

## 验证

### 构建日志中的成功标志

```
→ 修复 Flink POM 文件...
✓ flink-clients 已修复
✓ flink-python 已修复
✓ POM 修复完成
```

### 生成的文件

```bash
$ ls -lh /opt/modules/bigtop/output/flink/noarch/
-rw-r--r-- 1 root root 186M flink_3_2_0-1.17.2-1.el7.noarch.rpm
-rw-r--r-- 1 root root 4.6K flink_3_2_0-jobmanager-1.17.2-1.el7.noarch.rpm
-rw-r--r-- 1 root root 4.6K flink_3_2_0-taskmanager-1.17.2-1.el7.noarch.rpm
```

---

## 相关文件

### 容器内
- `/scripts/build/bigtop/fix-flink.sh` - Flink 修复脚本
- `/scripts/build/bigtop/build.sh` - 构建脚本（已修改）
- `/scripts/build/bigtop/patch/patch2-FLINK-FIXED.diff` - 空补丁

### 宿主机
- `jenkins-build-bigtop-gradle-resume.sh` - Jenkins 构建脚本
- `FLINK_BUILD_FINAL_SUCCESS.md` - 本文档

---

## 经验教训

1. **不要锁定文件**: `chattr +i` 会导致 `git checkout` 失败
2. **在正确的时机修复**: 在 `git checkout` 后立即应用修复
3. **使用独立脚本**: 比直接修改源码更可维护
4. **完全跳过测试**: 使用 `-Dmaven.test.skip=true` 而不是 `-DskipTests`
5. **设置完整 PATH**: 确保 Maven 可以在 rpmbuild 环境中找到

---

## 其他成功构建的组件

- ✅ Hadoop: 27 个 RPM 包
- ✅ Flink: 3 个 RPM 包
- ✅ ZooKeeper: 5 个 RPM 包
- ✅ Bigtop 工具包: 4 个 RPM 包

---

## 下一步

Hive 构建失败（Log4j 兼容性问题），需要单独处理。

---

**构建成功！Flink 问题已完全解决。** 🎉
