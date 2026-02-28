# Jenkins 优化构建脚本使用说明

## 概述

`jenkins-build-bigtop-optimized.sh` 是一个支持组件级断点续传的 Jenkins 构建脚本，相比原版脚本有以下优势：

### 主要改进

1. **组件级断点续传**：不再从头构建整个 Bigtop，而是跟踪每个组件的构建状态
2. **智能恢复**：失败后重新运行 Job，自动跳过已完成的组件
3. **清晰的进度显示**：实时显示哪些组件已完成、哪些待构建
4. **节省时间**：避免重复构建已完成的组件（可节省数小时）

### 支持的组件

脚本跟踪以下 Bigtop 组件的构建状态：

- hadoop
- zookeeper
- hbase
- spark
- flink
- kafka
- hive
- tez

## Jenkins 配置

### 1. 创建 Jenkins Job

1. 新建 "Freestyle project"
2. 配置 Git 仓库（指向你的项目）
3. 在 "Build" 部分添加 "Execute shell"
4. 输入以下命令：

```bash
#!/bin/bash
cd $WORKSPACE
chmod +x jenkins-build-bigtop-optimized.sh
./jenkins-build-bigtop-optimized.sh
```

### 2. 推荐的 Jenkins 配置

**General 设置：**
- ✓ Discard old builds (保留最近 10 次构建)
- ✓ This project is parameterized (可选，用于手动触发特定组件)

**Build Triggers：**
- ✓ Poll SCM: `H/30 * * * *` (每 30 分钟检查一次代码变更)
- 或使用 GitHub webhook 触发

**Post-build Actions：**
- ✓ Archive the artifacts: `**/*.rpm` (保存构建产物)
- ✓ E-mail Notification (构建失败时发送邮件)

## 使用场景

### 场景 1：首次完整构建

```
→ 执行 Jenkins Job
→ 脚本检测到没有已完成的组件
→ 按顺序构建所有组件：hadoop → zookeeper → hbase → ...
→ 如果某个组件失败（如 hadoop），构建停止
```

**输出示例：**
```
2. Bigtop 组件构建状态：
  → hadoop: 待构建
  → zookeeper: 待构建
  → hbase: 待构建
  ...

→ [1/8] 构建组件: hadoop
✗ hadoop 构建失败
```

### 场景 2：断点续传（修复后重试）

```
→ 修复 hadoop 构建问题（如修复 yarn-ui）
→ 重新运行 Jenkins Job
→ 脚本检测到 hadoop 失败，其他组件未构建
→ 从 hadoop 开始重新构建
→ hadoop 成功后，继续构建 zookeeper、hbase...
```

**输出示例：**
```
2. Bigtop 组件构建状态：
  → hadoop: 待构建
  → zookeeper: 待构建
  ...
  
  ⚠ 上次失败组件: hadoop
  → 将从 hadoop 开始重新构建

→ [1/8] 构建组件: hadoop
✓ hadoop 构建完成 (耗时: 1800s / 30m)

→ [2/8] 构建组件: zookeeper
✓ zookeeper 构建完成 (耗时: 300s / 5m)
```

### 场景 3：部分组件已完成

```
→ 假设 hadoop、zookeeper、hbase 已构建完成
→ spark 构建失败
→ 重新运行 Jenkins Job
→ 脚本自动跳过 hadoop、zookeeper、hbase
→ 直接从 spark 开始构建
```

**输出示例：**
```
2. Bigtop 组件构建状态：
  ✓ hadoop: 已完成 (15 个 RPM)
  ✓ zookeeper: 已完成 (3 个 RPM)
  ✓ hbase: 已完成 (8 个 RPM)
  → spark: 待构建
  → flink: 待构建
  ...

已完成: hadoop zookeeper hbase
待构建: spark flink kafka hive tez

→ [1/5] 构建组件: spark
```

## 构建状态管理

### 状态文件位置

脚本在容器内使用以下文件跟踪状态：

- `/tmp/bigtop_current_component` - 当前正在构建的组件
- `/tmp/bigtop_last_failed_component` - 上次失败的组件
- `/tmp/build_bigtop_completed` - Bigtop 完整构建完成标记
- `/data/rpm-package/` - RPM 包存储位置（用于判断组件是否完成）

### 判断组件完成的逻辑

脚本通过检查 RPM 包是否存在来判断组件是否已构建：

```bash
# 检查 hadoop 是否完成
find /data/rpm-package -name "hadoop-*.rpm" | wc -l
# 如果 > 0，则认为 hadoop 已完成
```

### 手动清理状态

如果需要强制重新构建某个组件，可以：

```bash
# 删除该组件的 RPM 包
docker exec centos1 rm -f /data/rpm-package/*hadoop*.rpm

# 清理失败标记
docker exec centos1 rm -f /tmp/bigtop_last_failed_component

# 重新运行 Jenkins Job
```

## 故障排查

### 问题 1：脚本报错 "容器未运行"

**原因：** centos1 容器未启动

**解决：**
```bash
docker-compose up -d centos1
# 等待 15 秒后重新运行 Job
```

### 问题 2：组件构建失败但状态未记录

**原因：** 可能是 Gradle 任务名称不匹配

**检查：**
```bash
# 进入容器查看可用的 Gradle 任务
docker exec centos1 bash -c "cd /opt/modules/bigtop && ./gradlew tasks | grep pkg"
```

**修复：** 更新脚本中的 `BIGTOP_COMPONENTS` 数组

### 问题 3：想要强制重新构建所有组件

**解决：**
```bash
# 清理所有 Bigtop RPM 包
docker exec centos1 bash -c "rm -rf /data/rpm-package/*bigtop*"

# 清理所有状态标记
docker exec centos1 bash -c "rm -f /tmp/build_*_completed /tmp/bigtop_*"

# 重新运行 Jenkins Job
```

## 性能对比

### 原版脚本（无断点续传）

```
首次构建失败在 hadoop (30分钟)
→ 修复问题
→ 重新运行：从头开始构建 hadoop (30分钟)
→ 再次失败在 spark (累计 2小时)
→ 修复问题
→ 重新运行：从头开始构建 hadoop + zookeeper + hbase + spark (2小时)
总耗时：4+ 小时（大量重复构建）
```

### 优化版脚本（组件级断点续传）

```
首次构建失败在 hadoop (30分钟)
→ 修复问题
→ 重新运行：只构建 hadoop (30分钟)
→ 继续构建 zookeeper、hbase，失败在 spark (累计 1.5小时)
→ 修复问题
→ 重新运行：跳过 hadoop、zookeeper、hbase，只构建 spark (20分钟)
总耗时：2.2 小时（节省 50%+ 时间）
```

## 最佳实践

1. **定期清理旧的 RPM 包**：避免磁盘空间不足
   ```bash
   docker exec centos1 bash -c "find /data/rpm-package -name '*.rpm' -mtime +7 -delete"
   ```

2. **监控构建日志**：每个组件的日志保存在容器内
   ```bash
   docker exec centos1 cat /opt/modules/bigtop/gradle_hadoop.log
   ```

3. **使用 Jenkins Pipeline**：可以进一步优化为并行构建（高级用法）

4. **设置构建超时**：在 Jenkins Job 配置中设置合理的超时时间（如 4 小时）

## 与原版脚本的兼容性

优化版脚本完全兼容原有的构建环境，可以直接替换 `jenkins-build-bigtop.sh`：

```bash
# 备份原脚本
mv jenkins-build-bigtop.sh jenkins-build-bigtop.sh.bak

# 使用优化版
cp jenkins-build-bigtop-optimized.sh jenkins-build-bigtop.sh
```

## 总结

优化版脚本通过组件级状态跟踪，实现了真正的断点续传功能，大幅减少了重复构建时间，特别适合：

- 大型项目的 CI/CD 流程
- 频繁失败需要调试的构建
- 资源受限的构建环境
- 需要快速迭代的开发场景

**关键优势：失败后重试，只构建失败的组件，不浪费时间重复构建已完成的部分！**
