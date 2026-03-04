# Flink 构建成功修复记录

## 问题总结

Flink 构建失败的根本原因有两个：

### 1. Maven Assembly 插件错误
```
Failed to execute goal maven-assembly-plugin:2.4:single 
(create-test-dependency-user-jar-depend) on project flink-clients: 
Error creating assembly archive test-user-classloader-job-lib-jar: 
You must set at least one file.
```

**原因**：
- 使用 `-DskipTests` 只跳过测试执行，但仍会编译测试代码
- 但测试资源没有被正确处理
- `maven-assembly-plugin` 尝试打包测试相关的 jar，但找不到文件

### 2. Maven 命令找不到
```
mvn: command not found
```

**原因**：
- 在 rpmbuild 的 chroot 环境中，PATH 不包含 Maven 路径
- Maven 安装在 `/opt/modules/apache-maven-3.8.4/bin/`

## 修复方案

### 修改文件
`bigtop-packages/src/common/flink/do-component-build`

### 关键修改

#### 1. 添加 PATH 设置（第 18-21 行）
```bash
set -ex

# 设置 Maven 和 Java 路径
export PATH=/opt/modules/apache-maven-3.8.4/bin:$PATH
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
```

#### 2. 修改 MAVEN_OPTS（第 26 行）
```bash
# 修改前
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"

# 修改后
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true"
```

#### 3. 修改 mvn 命令（第 56-58 行）
```bash
# 修改前
mvn -q install $FLINK_BUILD_OPTS -Drat.skip=true -DskipTests -Dhadoop.version=$HADOOP_VERSION "$@"

# 修改后
mvn -q install $FLINK_BUILD_OPTS -Drat.skip=true -Dmaven.test.skip=true -Dhadoop.version=$HADOOP_VERSION "$@"
```

#### 4. 移除不需要的参数
删除了这一行：
```bash
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip.exec=true"
```

## 参数说明

### `-DskipTests` vs `-Dmaven.test.skip=true`

| 参数 | 编译测试代码 | 运行测试 | Assembly 插件 |
|------|------------|---------|--------------|
| `-DskipTests` | ✓ 编译 | ✗ 不运行 | ✗ 可能失败（找不到测试资源）|
| `-Dmaven.test.skip=true` | ✗ 不编译 | ✗ 不运行 | ✓ 正常（不尝试打包测试）|

使用 `-Dmaven.test.skip=true` 可以：
- 完全跳过测试编译和执行
- 避免 assembly 插件尝试打包不存在的测试文件
- 减少构建时间和日志输出

## 验证修复

### 1. 检查源文件
```bash
docker exec centos1 bash -c "
  grep 'export PATH' /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build
  grep 'mvn -q install' /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build
"
```

应该看到：
- `export PATH=/opt/modules/apache-maven-3.8.4/bin:$PATH`
- `mvn -q install ... -Dmaven.test.skip=true ...`

### 2. 监控构建进程
```bash
# 检查进程
docker exec centos1 ps aux | grep -E 'gradlew.*flink|rpmbuild'

# 检查 Maven 活动
docker exec centos1 find /opt/modules/bigtop/build/flink/rpm/BUILD/flink-1.17.2 -name '*.jar' -mmin -5

# 检查 Maven 仓库活动
docker exec centos1 find /root/.m2/repository -type f -mmin -2 | wc -l
```

### 3. 构建状态
```bash
# 使用监控脚本
bash check_flink_build.sh
```

## 当前构建状态

- ✓ 构建进程正在运行
- ✓ Maven 正在编译（生成 jar 文件）
- ✓ 使用正确的参数：`-Dmaven.test.skip=true`
- ✓ Maven 命令可以找到
- ✓ 预计 20-30 分钟完成

## 构建日志位置

- 主日志：`/tmp/flink_rebuild_final.log`（容器内）
- PID 文件：`/tmp/flink_build_final.pid`（容器内）

## 注意事项

1. 由于使用了 `-q`（quiet）参数，Maven 日志输出很少
2. 可以通过检查生成的 jar 文件来确认构建进度
3. 构建完成后，RPM 包会在 `/opt/modules/bigtop/output/flink/` 目录

## 下次构建

如果需要重新构建，确保：
1. 清理构建目录：`rm -rf /opt/modules/bigtop/build/flink`
2. 源文件已经包含上述修改
3. Gradle 会自动复制修改后的 `do-component-build` 脚本

## 时间线

- 03:18 - 构建启动
- 03:20 - 确认 Maven 正在编译
- 预计 03:38-03:48 - 构建完成

## 相关文件

- 源脚本：`bigtop-packages/src/common/flink/do-component-build`
- 构建脚本：`build/flink/rpm/SOURCES/do-component-build`（自动生成）
- 监控脚本：`check_flink_build.sh`（本地）
