# 构建失败分析与解决方案

## 构建失败原因

构建在运行 106 分钟后失败，错误信息：
```
Gradle build daemon has been stopped: stop command received
```

**原因**：在构建过程中尝试停止 Daemon 导致构建中断。

## 根本问题

Bigtop 项目的 `gradle.properties` 文件中设置了：
```properties
org.gradle.daemon=true
org.gradle.jvmargs=-Xms2g -Xmx8g -XX:MaxMetaspaceSize=1g
```

这会覆盖命令行的 `--no-daemon` 参数，导致：
1. Daemon 仍然启动（即使命令行使用 `--no-daemon`）
2. 内存只有 8GB（不够 Flink 使用）
3. 产生双份日志：构建日志 + Daemon 日志

## 已应用的修复（下次构建生效）

已更新 `scripts/build/bigtop/build_bigtop_all.sh`，下次构建时会：

1. **覆盖项目配置**：在构建前重写 `gradle.properties`
   ```properties
   org.gradle.daemon=false
   org.gradle.jvmargs=-Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC
   ```

2. **清理 Daemon 日志**：构建前删除旧的 Daemon 日志文件
   ```bash
   rm -rf /root/.gradle/daemon/*/daemon-*.out.log
   ```

3. **强制终止残留进程**：使用 `pkill -9` 而不是普通 `pkill`

4. **构建后清理**：构建完成后清理 Daemon 进程和日志

## 当前状态

构建已失败（被中断），需要重新开始。

## 重新开始构建前的准备

在重新运行构建前，需要手动更新容器中的 `gradle.properties`：

```bash
# 1. 更新 gradle.properties（强制禁用 Daemon + 增加内存）
docker exec centos1 bash -c "
cat > /opt/modules/bigtop/gradle.properties << 'EOF'
# Gradle JVM 参数 - 增加内存以支持 Flink 等大型项目构建
org.gradle.jvmargs=-Xms4g -Xmx16g -XX:MaxMetaspaceSize=2g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError

# 强制禁用 Gradle daemon（避免后台进程和日志累积）
org.gradle.daemon=false

# 禁用并行构建（避免内存竞争）
org.gradle.parallel=false

# 配置文件缓存
org.gradle.caching=true
EOF
echo '✓ gradle.properties 已更新'
cat /opt/modules/bigtop/gradle.properties
"

# 2. 清理 Daemon 日志（释放 5GB+ 空间）
docker exec centos1 bash -c "
  rm -rf /root/.gradle/daemon/*/daemon-*.out.log
  rm -rf /opt/modules/bigtop/.gradle/daemon
  echo '✓ Daemon 日志已清理'
"

# 3. 清理旧的构建日志
docker exec centos1 bash -c "
  rm -f /opt/modules/bigtop/gradle_build.log
  echo '✓ 旧构建日志已清理'
"
```

## 重新开始构建

执行完上面的准备步骤后，重新运行 Jenkins 构建：

```bash
# 方式 1：通过 Jenkins 重新触发构建
# 在 Jenkins 页面点击 "Build Now"

# 方式 2：手动运行构建脚本
docker exec centos1 bash -l -c "/scripts/build/bigtop/build_bigtop_all.sh"
```

## 预期效果

更新配置后，下次构建：
- ✓ Daemon 将被真正禁用（不会有后台进程）
- ✓ 内存增加到 16GB（足够 Flink 使用）
- ✓ 只有一份日志：`/opt/modules/bigtop/gradle_build.log`
- ✓ 日志大小预计：2-5GB（而不是 10GB+）
- ✓ 增量构建：已完成的组件（如 Hadoop）会自动跳过

## 监控当前构建

```bash
# 查看构建进度（最后 20 行）
docker exec centos1 tail -20 /opt/modules/bigtop/gradle_build.log

# 查看日志大小变化
docker exec centos1 watch -n 10 'du -h /opt/modules/bigtop/gradle_build.log /root/.gradle/daemon/5.6.4/daemon-*.out.log 2>/dev/null'

# 检查是否有错误
docker exec centos1 tail -100 /opt/modules/bigtop/gradle_build.log | grep -E "FAILURE|ERROR"
```

## 总结

- **当前构建**：继续运行，不要停止
- **日志大小**：5.4GB x 2 = 10.8GB（可接受，之前是 50-100GB）
- **下次构建**：Daemon 将被真正禁用，日志减少到 2-5GB
- **构建完成后**：运行上面的清理命令释放空间
