# RPM 包同步完成

## 同步结果

✅ **所有构建好的 RPM 包已从容器同步到宿主机**

**同步时间**: 2026-03-10  
**总大小**: 2.7G

## 宿主机 RPM 包目录结构

### Ambari (152M)
位置: `/data/rpm-package/ambari/`

9 个 RPM 包:
- ambari-server-2.8.0.0-0.x86_64.rpm (122M)
- ambari-agent-2.8.0.0-0.x86_64.rpm (31M)
- ambari-web, ambari-admin, ambari-views 等

### Bigtop 组件 (2.5G)
位置: `/data/rpm-package/bigtop/`

| 组件 | RPM 数量 | 大小 | 状态 |
|------|---------|------|------|
| bigtop-groovy | 2 | 38M | ✅ 完成 |
| bigtop-jsvc | 4 | 408K | ✅ 完成 |
| bigtop-select | 2 | 56K | ✅ 完成 |
| bigtop-utils | 2 | 44K | ✅ 完成 |
| flink | 3 | 219M | ✅ 完成 |
| hadoop | 54 | 846M | ✅ 完成 |
| hbase | 21 | 1.1G | ✅ 完成 |
| hive | 9 | 350M | ✅ 完成 |
| zookeeper | 10 | 37M | ✅ 完成 |
| spark | 0 | 33M | ⚠️ 未完成 |

**总计**: 107 个 RPM 包（不含 src.rpm）

## 同步的重要性

### 问题背景
之前 Jenkins 脚本无法识别已完成的组件，导致：
- Hadoop、HBase 等组件重复构建
- 浪费大量构建时间
- 构建日志混乱

### 解决方案
将容器中 `/opt/modules/bigtop/output/` 的所有 RPM 包同步到 `/data/rpm-package/bigtop/`，这样：
1. Jenkins 脚本可以正确检测已完成的组件
2. Gradle 会跳过已完成的任务（显示 UP-TO-DATE）
3. 只构建未完成或失败的组件

## Jenkins 脚本检测逻辑

`jenkins-build-bigtop-gradle-resume.sh` 中的检测代码：

```bash
COMPLETED_COMPONENTS=$(docker exec centos1 bash -c "
    cd /data/rpm-package/bigtop 2>/dev/null || exit 0
    for dir in */; do
        component=\${dir%/}
        rpm_count=\$(find \"\$dir\" -name '*.rpm' -not -name '*.src.rpm' 2>/dev/null | wc -l)
        if [ \$rpm_count -gt 0 ]; then
            echo \"\$component\"
        fi
    done
")
```

现在可以正确识别 9 个已完成的组件！

## 验证结果

在宿主机上运行检测：
```bash
cd /data/rpm-package/bigtop
for dir in */; do
    component=${dir%/}
    rpm_count=$(find "$dir" -name '*.rpm' -not -name '*.src.rpm' 2>/dev/null | wc -l)
    if [ $rpm_count -gt 0 ]; then
        echo "✓ $component ($rpm_count 个 RPM)"
    fi
done
```

输出：
```
✓ bigtop-groovy (2 个 RPM)
✓ bigtop-jsvc (4 个 RPM)
✓ bigtop-select (2 个 RPM)
✓ bigtop-utils (2 个 RPM)
✓ flink (3 个 RPM)
✓ hadoop (54 个 RPM)
✓ hbase (21 个 RPM)
✓ hive (9 个 RPM)
✓ zookeeper (10 个 RPM)
```

## 下一步

现在可以运行 Jenkins 构建脚本，它会：

1. **跳过已完成的组件**:
   - bigtop-groovy, bigtop-jsvc, bigtop-select, bigtop-utils
   - flink, hadoop, hbase, hive, zookeeper

2. **构建未完成的组件**:
   - spark (0 个 RPM，需要构建)
   - 其他未构建的组件

3. **增量构建**:
   - 如果某个组件构建失败，重新运行脚本只会重试失败的组件
   - 已成功的组件不会重新构建

## 运行 Jenkins 构建

```bash
./jenkins-build-bigtop-gradle-resume.sh
```

脚本会显示：
```
→ 检查已完成的组件...
✓ 已完成的组件：
  - bigtop-groovy
  - bigtop-jsvc
  - bigtop-select
  - bigtop-utils
  - flink
  - hadoop
  - hbase
  - hive
  - zookeeper
  共 9 个组件
```

## 目录映射关系

| 容器路径 | 宿主机路径 | 说明 |
|---------|-----------|------|
| `/opt/modules/bigtop/output/` | - | Gradle 构建输出 |
| `/data/rpm-package/bigtop/` | `/data/rpm-package/bigtop/` | 标准 RPM 存储位置（容器和宿主机共享） |
| `/data/rpm-package/ambari/` | `/data/rpm-package/ambari/` | Ambari RPM 存储位置 |

## 同步命令记录

### 容器内同步（output → rpm-package）
```bash
docker exec centos1 bash -c "
for dir in /opt/modules/bigtop/output/*/; do
    component=\$(basename \"\$dir\")
    target_dir=\"/data/rpm-package/bigtop/\$component\"
    mkdir -p \"\$target_dir\"
    find \"\$dir\" -name '*.rpm' -not -name '*.src.rpm' -exec cp {} \"\$target_dir/\" \;
done
"
```

### 容器到宿主机同步
```bash
# Bigtop 组件
docker cp centos1:/data/rpm-package/bigtop/. /data/rpm-package/bigtop/

# Ambari 组件
docker cp centos1:/data/rpm-package/ambari/. /data/rpm-package/ambari/
```

---

**同步完成时间**: 2026-03-10  
**状态**: ✅ 成功  
**总大小**: 2.7G (Ambari 152M + Bigtop 2.5G)
