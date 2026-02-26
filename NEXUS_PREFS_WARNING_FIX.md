# Nexus Java Preferences 警告修复

## 问题描述

Nexus 日志中每 30 秒出现一次警告：
```
WARN [Timer-0] *SYSTEM java.util.prefs - Could not lock User prefs. Unix error code 2.
WARN [Timer-0] *SYSTEM java.util.prefs - Couldn't flush user prefs: java.util.prefs.BackingStoreException: Couldn't get file lock.
```

## 原因分析

1. **Java Preferences API**: Java 应用使用 `java.util.prefs` 包来存储用户和系统偏好设置
2. **默认路径**: 默认情况下，Java 尝试在用户主目录 `~/.java/.userPrefs` 创建偏好文件
3. **权限问题**: Nexus 容器以 UID 200 的 nexus 用户运行，默认主目录可能没有写权限或无法创建锁文件
4. **Unix error code 2**: 表示 "No such file or directory"，即无法创建或访问偏好目录

## 影响评估

**这是一个良性警告，不影响 Nexus 核心功能**：
- ✅ 仓库管理正常
- ✅ 代理功能正常
- ✅ Maven/Gradle 构建正常
- ✅ 用户认证正常
- ❌ 仅影响 Java 应用的某些用户偏好设置持久化

## 解决方案

### 修改 docker-compose.yaml

在 Nexus 服务的环境变量中指定 Java Preferences 的存储路径：

```yaml
services:
  nexus:
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Xms4g -Xmx8g -Djava.util.prefs.systemRoot=/nexus-data/.java/.systemPrefs -Djava.util.prefs.userRoot=/nexus-data/.java/.userPrefs
```

### 创建并设置权限

```bash
# 创建目录
mkdir -p common/data/nexus-data/.java/.userPrefs
mkdir -p common/data/nexus-data/.java/.systemPrefs

# 设置权限（UID 200 是 Nexus 容器内的 nexus 用户）
chown -R 200:200 common/data/nexus-data/.java
```

### 重启容器

```bash
docker-compose down nexus
docker-compose up -d nexus
```

## 验证修复

### 1. 检查日志中是否还有警告
```bash
docker logs nexus 2>&1 | grep -i "prefs"
```
应该没有输出或只有初始化信息

### 2. 验证 Nexus 功能
```bash
curl -s http://localhost:8081/
```
应该返回 Nexus 的 HTML 页面

### 3. 检查目录权限
```bash
ls -la common/data/nexus-data/.java/
```
应该显示 UID 200 拥有的目录

## 技术细节

### Java Preferences API 参数说明

- `-Djava.util.prefs.userRoot=/path`: 指定用户偏好存储路径
- `-Djava.util.prefs.systemRoot=/path`: 指定系统偏好存储路径

### 为什么使用 /nexus-data 目录

1. **持久化**: `/nexus-data` 是挂载的卷，数据会持久化到宿主机
2. **权限**: Nexus 用户对该目录有完全的读写权限
3. **备份**: 随 nexus-data 一起备份，不会丢失配置

### 其他解决方案（不推荐）

#### 方案 1: 完全禁用 Preferences
```yaml
INSTALL4J_ADD_VM_PARAMS=-Xms4g -Xmx8g -Djava.util.prefs.PreferencesFactory=java.util.prefs.FileSystemPreferencesFactory
```
缺点：可能影响某些插件功能

#### 方案 2: 使用内存存储
```yaml
INSTALL4J_ADD_VM_PARAMS=-Xms4g -Xmx8g -Djava.util.prefs.PreferencesFactory=java.util.prefs.MemoryPreferencesFactory
```
缺点：重启后丢失所有偏好设置

## 相关文件

- `docker-compose.yaml` - Nexus 容器配置
- `common/data/nexus-data/.java/` - Java Preferences 存储目录

## 参考资料

- [Java Preferences API Documentation](https://docs.oracle.com/javase/8/docs/api/java/util/prefs/Preferences.html)
- [Nexus Repository Docker Image](https://hub.docker.com/r/sonatype/nexus3)
- [Unix Error Codes](https://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html)

## 更新日志

- 2026-02-26: 修复 Java Preferences 警告，指定自定义存储路径
