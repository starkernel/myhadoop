# 构建模式对比分析

## 当前手动构建 vs Jenkins 脚本构建

### 1. 构建命令对比

#### 当前手动构建（测试 Flink）
```bash
./gradlew flink-rpm \
  -PparentDir=/usr/bigtop \
  -Dbuildwithdeps=true \
  --no-daemon \
  --warn \
  -x test
```

#### Jenkins 脚本构建（完整 Bigtop）
```bash
gradle "${ALL_COMPONENTS[@]}" \
  -PparentDir=/usr/bigtop \
  -Dbuildwithdeps=true \
  -PpkgSuffix \
  --no-daemon \
  --max-workers=4 \
  --warn \
  -x test \
  --console=plain
```

### 2. 关键差异

| 项目 | 手动构建 | Jenkins 构建 | 影响 |
|------|---------|-------------|------|
| **构建范围** | 只构建 flink-rpm | 构建所有组件（30+ 个） | ✓ 兼容 |
| **并行控制** | 无限制 | --max-workers=4 | ⚠ 需注意 |
| **输出格式** | 默认（rich） | --console=plain | ✓ 兼容 |
| **包后缀** | 无 | -PpkgSuffix | ✓ 兼容 |
| **其他参数** | 相同 | 相同 | ✓ 完全兼容 |

### 3. 环境变量对比

#### 当前手动构建
```bash
# 无特殊环境变量（使用 do-component-build 中的配置）
```

#### Jenkins 构建
```bash
# Gradle 配置
export GRADLE_OPTS="-Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC"
export GRADLE_OPTS="${GRADLE_OPTS} -Dorg.gradle.daemon=false"

# Maven 配置（通过 Jenkins 脚本）
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC"
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true -DskipTests=true"
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true"
```

**注意**：Jenkins 脚本设置的 MAVEN_OPTS 会被 do-component-build 中的设置覆盖！

### 4. Flink do-component-build 配置

#### 当前修复后的配置
```bash
# PATH 设置
export PATH=/opt/modules/apache-maven-3.8.4/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:$PATH
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk

# Maven 内存配置
export MAVEN_OPTS="${MAVEN_OPTS} -Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g"
export MAVEN_OPTS="${MAVEN_OPTS} -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError"

# 跳过测试
export MAVEN_OPTS="${MAVEN_OPTS} -Dmaven.test.skip=true"

# 减少日志输出
export MAVEN_OPTS="${MAVEN_OPTS} -Dorg.slf4j.simpleLogger.defaultLogLevel=warn"
export MAVEN_OPTS="${MAVEN_OPTS} -Drat.skip=true -Dcheckstyle.skip=true -Denforcer.skip=true"

# 跳过前端检查
export MAVEN_OPTS="${MAVEN_OPTS} -Dskip.npm=true"

# POM 修复（跳过测试 assembly）
if [ -f flink-clients/pom.xml ]; then
  # 为测试 assembly 添加 <skip>true</skip>
  ...
fi

# Maven 构建命令
mvn -q install $FLINK_BUILD_OPTS \
  -Drat.skip=true \
  -Dmaven.test.skip=true \
  -Dassembly.skipAssembly=true \
  -Dmaven.source.skip=true \
  -Dhadoop.version=$HADOOP_VERSION "$@"
```

### 5. 兼容性分析

#### ✓ 完全兼容的部分
1. **Gradle 参数**：手动构建使用的参数是 Jenkins 构建的子集
2. **Maven 配置**：do-component-build 中的配置会覆盖 Jenkins 的 MAVEN_OPTS
3. **测试跳过**：两者都跳过测试（-x test 和 -Dmaven.test.skip=true）
4. **日志级别**：都使用 --warn 和 WARN 级别

#### ⚠ 需要注意的差异

1. **--max-workers=4**
   - Jenkins 构建限制并行任务数为 4
   - 手动构建无限制（可能使用更多 CPU）
   - **影响**：Jenkins 构建可能稍慢，但更稳定
   - **建议**：保持 Jenkins 的限制，避免内存峰值

2. **--console=plain**
   - Jenkins 使用纯文本输出
   - 手动构建使用默认的 rich 输出
   - **影响**：仅影响日志格式，不影响构建结果
   - **建议**：无需修改

3. **-PpkgSuffix**
   - Jenkins 构建添加包后缀参数
   - 手动构建未使用
   - **影响**：可能影响 RPM 包命名
   - **建议**：手动构建也可以添加此参数

### 6. 关键修复的兼容性

#### Flink 修复内容
1. **PATH 设置** - ✓ 兼容
   - 在 do-component-build 中设置，不受 Jenkins 影响
   
2. **POM 修复** - ✓ 兼容
   - 在 Maven 构建前执行，对 Jenkins 透明
   
3. **Maven 参数** - ✓ 兼容
   - do-component-build 中的参数会覆盖 Jenkins 的 MAVEN_OPTS

### 7. Jenkins 构建流程

```
Jenkins 脚本
  ↓
调用 build_bigtop_all.sh
  ↓
应用补丁（build1_0_*.sh）
  ↓
设置 GRADLE_OPTS 和 gradle.properties
  ↓
执行 gradle 构建所有组件
  ↓
  对于 flink-rpm 任务：
    ↓
  调用 rpmbuild
    ↓
  执行 do-component-build（我们修复的脚本）
    ↓
  设置 PATH 和 MAVEN_OPTS（覆盖 Jenkins 的设置）
    ↓
  修复 flink-clients/pom.xml
    ↓
  执行 mvn install
    ↓
  构建成功
```

### 8. 结论

#### ✓ 当前修复完全兼容 Jenkins 构建

原因：
1. 所有修复都在 `do-component-build` 脚本中
2. `do-component-build` 由 rpmbuild 调用，不受 Gradle 参数影响
3. Maven 配置在 `do-component-build` 中设置，会覆盖外部的 MAVEN_OPTS
4. POM 修复在 Maven 构建前执行，对外部透明

#### 建议

1. **无需修改 Jenkins 脚本**
   - 当前的 `jenkins-build-bigtop-gradle-resume.sh` 可以直接使用
   - Flink 修复会自动生效

2. **可选优化**
   - 在手动测试时也可以添加 `--max-workers=4` 和 `--console=plain`
   - 这样可以更接近 Jenkins 的构建环境

3. **验证方法**
   - 当前 Flink 构建成功后，直接运行 Jenkins 脚本
   - 应该能够成功构建所有组件，包括 Flink

### 9. 测试建议

#### 当前 Flink 构建完成后

1. **验证 RPM 包**
   ```bash
   docker exec centos1 ls -lh /opt/modules/bigtop/output/flink/
   ```

2. **测试 Jenkins 完整构建**
   ```bash
   bash jenkins-build-bigtop-gradle-resume.sh
   ```

3. **监控 Flink 构建**
   - Jenkins 构建到 Flink 时，检查日志确认修复生效
   - 应该看到 "✓ 跳过 flink-clients 测试 assembly..."

### 10. 总结

| 项目 | 状态 | 说明 |
|------|------|------|
| 构建命令兼容性 | ✓ 完全兼容 | 手动构建是 Jenkins 的子集 |
| 环境变量兼容性 | ✓ 完全兼容 | do-component-build 会覆盖 |
| Flink 修复兼容性 | ✓ 完全兼容 | 修复对 Jenkins 透明 |
| 构建结果一致性 | ✓ 预期一致 | 相同的源码和配置 |
| 需要修改 Jenkins | ✗ 不需要 | 可以直接使用 |

**结论**：当前的 Flink 修复完全兼容 Jenkins 构建模式，无需修改 Jenkins 脚本。
