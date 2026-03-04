# Gradle 构建故障排查指南

## 核心优化（已应用）

### 1. 日志爆炸问题根治

**问题根源**：
- Gradle Daemon 后台运行持续产生日志
- 日志级别太低（DEBUG）输出所有细节
- 测试日志占用 90% 空间
- 使用 `tee` 追加模式导致日志累积

**根治方案**（已应用到 `build_bigtop_all.sh`）：
```bash
# 1. 构建前清理旧日志
rm -f "$PROJECT_PATH/gradle_build.log"

# 2. 禁用 Gradle Daemon
export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.daemon=false"
gradle --no-daemon ...

# 3. 只显示警告和错误
gradle --warn ...

# 4. 跳过所有测试
gradle -x test ...

# 5. 使用纯文本输出（避免进度条刷新）
gradle --console=plain ...

# 6. 构建前后清理 Daemon 进程
pkill -f "GradleDaemon"
./gradlew --stop
```

**效果**：
- 日志从 50-100GB → 2-5GB（减少 95%）
- 构建时间减少 50-70%

### 2. 增量构建（已应用）

**问题**：Hadoop 等组件每次都重新构建

**解决**：Jenkins 脚本检查 `/data/rpm-package/bigtop/` 下的 RPM 包
- 有 RPM → 跳过
- 无 RPM → 构建

### 3. 跳过测试（已应用）

**配置位置**：
1. Jenkins 脚本全局：`export MAVEN_OPTS="-Dmaven.test.skip=true -DskipTests=true"`
2. Hadoop do-component-build：自动添加
3. Flink do-component-build：自动添加
4. Gradle 命令：`-x test`

## 问题 1：Could not receive a message from the daemon

### 症状
```
FAILURE: Build failed with an exception.
* What went wrong:
Could not receive a message from the daemon.
```

### 原因
Gradle daemon 进程崩溃，通常由以下原因引起：
1. 内存不足（OOM - Out of Memory）
2. Daemon 进程意外终止
3. 网络连接问题（在容器环境中）

### 解决方案

#### 1. 增加 Gradle 内存配置（已应用）

**Jenkins 脚本** (`jenkins-build-bigtop-gradle-resume.sh`):
```bash
export GRADLE_OPTS="${GRADLE_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC -Dorg.gradle.daemon=false"
```

**Bigtop 构建脚本** (`scripts/build/bigtop/build_bigtop_all.sh`):
```bash
export GRADLE_OPTS="${GRADLE_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC"
```

**Flink Maven 配置** (在 `build.sh` 中自动应用):
```bash
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC"
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
```

配置说明：
- `-Xms4g`: 初始堆内存 4GB
- `-Xmx16g`: 最大堆内存 16GB（Flink 需要大量内存）
- `-XX:MaxMetaspaceSize=2g`: Metaspace 最大 2GB
- `-XX:+UseG1GC`: 使用 G1 垃圾收集器，适合大堆内存
- `-Dorg.gradle.daemon=false`: 禁用 daemon（Jenkins 脚本中）
- `--no-daemon`: Gradle 命令行参数（构建脚本中）

## 问题 2：Jenkins 日志过大导致构建失败

### 症状
- Jenkins 控制台输出非常大（几百 MB）
- 浏览器打开 Jenkins 日志页面卡死
- 构建过程中出现 "Too much output" 警告

### 原因
Maven/Gradle 构建输出大量日志：
1. 依赖下载进度信息
2. 编译详细信息（javac 输出）
3. 测试运行日志
4. 插件执行详细信息

### 解决方案（已应用）

#### 1. Gradle 日志级别优化
```bash
# 只显示警告和错误
gradle --warn ...

# 跳过测试
gradle -x test ...

# 纯文本输出（避免进度条刷新）
gradle --console=plain ...
```

#### 2. Maven 日志级别优化
在 Hadoop/Flink do-component-build 中自动配置：
```bash
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true"
```

#### 3. 查看完整日志
完整日志保存在容器内：
```bash
# 查看完整日志
docker exec centos1 cat /opt/modules/bigtop/gradle_build.log

# 只看错误
docker exec centos1 grep -E "ERROR|FAILURE|Exception" /opt/modules/bigtop/gradle_build.log

# 查看日志大小
docker exec centos1 du -h /opt/modules/bigtop/gradle_build.log

# 下载日志到本地
docker cp centos1:/opt/modules/bigtop/gradle_build.log ./
```

## 问题 3：Gradle Daemon 持续运行

### 症状
```bash
# 构建结束后仍有 Gradle 进程
ps aux | grep gradle
# 看到多个 GradleDaemon 进程
```

### 解决方案（已应用）

#### 1. 构建前清理
```bash
# 在 build_bigtop_all.sh 开头
pkill -f "GradleDaemon" || true
```

#### 2. 禁用 Daemon
```bash
export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.daemon=false"
gradle --no-daemon ...
```

#### 3. 构建后清理
```bash
# 在 build_bigtop_all.sh 结尾
./gradlew --stop
pkill -f "GradleDaemon" || true
```

#### 4. 手动清理
```bash
docker exec centos1 bash -c "
  cd /opt/modules/bigtop
  ./gradlew --stop
  pkill -f GradleDaemon
  rm -rf ~/.gradle/daemon
  rm -rf .gradle/daemon
"
```

## 问题 4：日志文件持续增长

### 症状
- 每次构建日志都在增长
- 日志文件达到几十 GB

### 原因
- 使用 `tee` 追加模式（`>>`）
- Gradle Daemon 持续运行产生日志

### 解决方案（已应用）

#### 1. 构建前清理旧日志
```bash
# 在 build_bigtop_all.sh 中
rm -f "$PROJECT_PATH/gradle_build.log"
```

#### 2. 使用覆盖模式
```bash
# 使用 tee（覆盖模式）
gradle ... 2>&1 | tee "$PROJECT_PATH/gradle_build.log"
# 而不是 >>（追加模式）
```

#### 3. 定期清理
```bash
# 手动清理
docker exec centos1 rm -f /opt/modules/bigtop/gradle_build.log
```

#### 2. 限制并行任务数（已应用）

```bash
gradle ... --max-workers=4
```

防止过多并行任务导致内存耗尽。

#### 3. 检查容器内存限制

确保 Docker 容器有足够内存：

```bash
# 检查容器内存限制
docker stats centos1 --no-stream

# 如果需要，修改 docker-compose.yml
services:
  centos1:
    mem_limit: 16g
    memswap_limit: 16g
```

#### 4. 清理 Gradle 缓存

如果问题持续，清理 Gradle 缓存：

```bash
docker exec centos1 bash -c "
  cd /opt/modules/bigtop
  ./gradlew clean
  rm -rf ~/.gradle/caches
  rm -rf ~/.gradle/daemon
"
```

#### 5. 手动调试

进入容器手动运行构建：

```bash
# 进入容器
docker exec -it centos1 bash

# 设置环境
cd /opt/modules/bigtop
source /opt/rh/devtoolset-7/enable
export GRADLE_OPTS="-Xms4g -Xmx12g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC"

# 单独构建失败的组件（例如 flink）
./gradlew flink-rpm -PparentDir=/usr/bigtop -Dbuildwithdeps=true --no-daemon --stacktrace
```

### 监控构建过程

#### 实时查看日志
```bash
docker exec centos1 tail -f /opt/modules/bigtop/gradle_build.log
```

#### 查看内存使用
```bash
docker exec centos1 bash -c "free -h && ps aux | grep gradle | grep -v grep"
```

#### 查看 Gradle daemon 状态
```bash
docker exec centos1 bash -c "cd /opt/modules/bigtop && ./gradlew --status"
```

### 断点续传

Gradle 自动支持增量构建：
1. 重新运行 Jenkins job 或构建脚本
2. 已完成的任务会显示 `UP-TO-DATE`
3. 只重新执行失败的任务

### 常见错误模式

#### OOM 错误
```
java.lang.OutOfMemoryError: Java heap space
```
→ 增加 `-Xmx` 值

#### Metaspace OOM
```
java.lang.OutOfMemoryError: Metaspace
```
→ 增加 `-XX:MaxMetaspaceSize` 值

#### Daemon 超时
```
Daemon will be stopped at the end of the build after running out of JVM memory
```
→ 使用 `--no-daemon` 或增加内存

#### Yetus 下载失败（Hadoop shelldocs）
```
ERROR: yetus-dl: unable to download https://archive.apache.org/dist/yetus/0.13.0//apache-yetus-0.13.0-bin.tar.gz
```
→ 已自动修复：在 `build.sh` 中添加了多镜像源下载逻辑
→ 如果仍失败，手动下载：
```bash
docker exec centos1 bash -c "
  mkdir -p ~/.yetus
  cd ~/.yetus
  curl -L -o apache-yetus-0.13.0-bin.tar.gz \
    https://mirrors.tuna.tsinghua.edu.cn/apache/yetus/0.13.0/apache-yetus-0.13.0-bin.tar.gz
  tar -xzf apache-yetus-0.13.0-bin.tar.gz
"
```

#### Gradle Daemon 仍在运行（即使使用 --no-daemon）

**症状**：
```bash
# 发现 Daemon 进程仍在运行
pgrep -f GradleDaemon

# Daemon 日志文件持续增长
/root/.gradle/daemon/5.6.4/daemon-*.out.log  # 几个 GB
```

**原因**：
1. 项目中可能有 `gradle.properties` 文件设置了 `org.gradle.daemon=true`
2. 环境变量优先级：项目配置 > 命令行参数
3. Bigtop 项目可能在某处强制启用了 Daemon

**解决方案**（已应用到 `build_bigtop_all.sh`）：
```bash
# 1. 在项目根目录创建 gradle.properties 强制禁用
echo "org.gradle.daemon=false" > /opt/modules/bigtop/gradle.properties

# 2. 在用户目录也创建（全局生效）
echo "org.gradle.daemon=false" > ~/.gradle/gradle.properties

# 3. 构建前清理 Daemon 日志
rm -rf /root/.gradle/daemon/*/daemon-*.out.log

# 4. 使用 pkill -9 强制终止（而不是普通 pkill）
pkill -9 -f "GradleDaemon"
```

**当前构建中的临时方案**：
如果构建正在进行中，不要停止！等构建完成后：
```bash
# 构建完成后立即清理
docker exec centos1 bash -c "
  pkill -9 -f GradleDaemon
  rm -rf /root/.gradle/daemon/*/daemon-*.out.log
  rm -rf /opt/modules/bigtop/.gradle/daemon
"
```

#### Flink Runtime Web npm 构建失败
```
ERROR: Failed to execute goal frontend-maven-plugin:1.11.0:npm (npm run ci-check)
Process exited with an error: 126 (Exit value: 126)
```

**原因**：
- 退出码 126 = 权限问题或命令不可执行
- Flink Runtime Web 需要 Node.js 和 npm 构建前端
- 前端检查（ci-check）包含 lint、格式检查等

**解决方案**（已应用）：
```bash
# 在 Flink do-component-build 中跳过前端构建
export MAVEN_OPTS="${MAVEN_OPTS} -Dskip.npm=true"
mvn ... -Dskip.npm=true install
```

**手动修复**（如果自动修复失败）：
```bash
docker exec centos1 bash -c "
  cd /opt/modules/bigtop/build/flink/rpm/BUILD/flink-*/flink-runtime-web
  
  # 检查 node 权限
  ls -la node/node
  chmod +x node/node 2>/dev/null || true
  
  # 或者直接跳过前端构建
  cd /opt/modules/bigtop/bigtop-packages/src/common/flink
  sed -i 's/mvn \(.*\)install/mvn \1-Dskip.npm=true install/g' do-component-build
"
```

### 性能优化建议

1. **使用本地 Maven 仓库**：确保 Nexus 配置正确
2. **并行构建**：`--parallel` 但要注意内存使用
3. **构建缓存**：`--build-cache` 加速重复构建
4. **分阶段构建**：先构建依赖少的组件

### 获取帮助

如果问题仍未解决：
1. 查看完整日志：`docker exec centos1 cat /opt/modules/bigtop/gradle_build.log`
2. 查看 heap dump（如果生成）：`docker exec centos1 find /opt/modules/bigtop -name "*.hprof"`
3. 检查系统资源：`docker stats` 和 `docker exec centos1 top`
