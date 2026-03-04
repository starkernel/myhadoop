# Flink 构建失败修复

## 问题 1：日志爆炸（12GB）

### 根本原因
Flink 的 `do-component-build` 脚本中使用了 `mvn -X` 参数（DEBUG 模式），导致：
- 92万行 DEBUG 日志
- 日志文件 12GB（2小时构建）
- 双份日志（构建日志 + Daemon 日志）= 24GB

### 修复方案
移除 Flink do-component-build 中的 `-X` 参数：

```bash
# 修改前
mvn -X -q -Dskip.npm=true install ...

# 修改后
mvn -q -Dskip.npm=true install ...
```

### 预期效果
- DEBUG 日志：92万行 → 0行
- 日志大小：12GB → 1-2GB（减少 85-90%）

## 问题 2：Flink Clients 构建失败

### 错误信息
```
Failed to execute goal maven-assembly-plugin:2.4:single 
(create-test-dependency-user-jar-depend) on project flink-clients: 
Error creating assembly archive test-user-classloader-job-lib-jar: 
You must set at least one file.
```

### 根本原因
- 使用 `-DskipTests` 会跳过测试执行但仍编译测试代码
- `maven-assembly-plugin` 在 `process-test-classes` 阶段执行
- Assembly 配置引用 `${project.build.testOutputDirectory}`
- 但测试类没有被编译（因为使用了 `-DskipTests`），目录为空
- Assembly 插件报错："You must set at least one file"

### 修复方案
使用 `-Dmaven.test.skip=true` 替代 `-DskipTests`：

```bash
# 错误的方式（会导致 assembly 失败）
mvn install -DskipTests

# 正确的方式（完全跳过测试，包括编译）
mvn install -Dmaven.test.skip=true
```

区别：
- `-DskipTests`：编译测试代码但不运行测试
- `-Dmaven.test.skip=true`：完全跳过测试（不编译也不运行）

### 已应用的修复（2026-03-03）

修改了容器内的 `do-component-build` 脚本：

```bash
# 修改前
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"
mvn -q install -DskipTests ...

# 修改后
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true"
mvn -q install -Dmaven.test.skip=true ...
```

## 已应用的修复

### 1. 容器内立即修复（2026-03-03 00:38 UTC）
```bash
# 已在 centos1 容器中修复
# 位置：/opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build

# 关键修改：
# 1. 移除 -DskipTests，只使用 -Dmaven.test.skip=true
# 2. 移除不需要的 -Dmaven.test.skip.exec=true
# 3. 清理了 Flink 构建目录
```

### 2. 验证修复
```bash
# 检查修改
docker exec centos1 grep -n 'maven.test.skip\|skipTests' \
  /opt/modules/bigtop/bigtop-packages/src/common/flink/do-component-build

# 应该只看到 -Dmaven.test.skip=true，没有 -DskipTests
```

## 重新构建 Flink

### 通过 Jenkins 重新构建（推荐）

修复已应用到容器中，现在可以重新构建：

1. **访问 Jenkins**：http://192.168.0.150:8080
2. **找到 Bigtop 构建任务**
3. **点击 "Build Now"** 重新触发构建

Jenkins 会自动：
- 使用修复后的 `do-component-build` 脚本
- 跳过已成功的组件（如 Hadoop）
- 只重新构建 Flink

### 手动构建（备选方案）

如果需要手动构建 Flink：

```bash
# 只构建 Flink
docker exec centos1 bash -c "
  cd /opt/modules/bigtop
  ./gradlew flink-rpm -PparentDir=/usr/bigtop -Dbuildwithdeps=true --no-daemon --warn -x test
"
```

## 预期结果

### 日志大小对比
| 构建阶段 | 修复前 | 修复后 | 改善 |
|---------|--------|--------|------|
| 2小时构建 | 12GB | 1-2GB | 85-90% |
| 完整构建 | 50-100GB | 5-10GB | 90% |

### 构建时间
- Flink 构建：23分钟（跳过测试）
- 完整构建：预计 2-3小时

## 验证修复

构建开始后，监控日志：
```bash
# 查看日志增长速度
docker exec centos1 watch -n 10 'du -h /opt/modules/bigtop/gradle_build.log'

# 检查是否还有 DEBUG 日志
docker exec centos1 tail -100 /opt/modules/bigtop/gradle_build.log | grep '\[DEBUG\]'
# 应该没有输出

# 检查 Daemon 日志
docker exec centos1 du -sh /root/.gradle/daemon
```
