# CentOS1 容器故障排查指南

## 问题现象

容器启动后自动停止，状态显示 `Exited (128)`

## 根本原因

容器启动脚本 `setup_github_code.sh` 在初始化时尝试从 GitHub 克隆大型代码仓库（Ambari），由于网络超时导致克隆失败，脚本使用了 `set -e` 参数，任何命令失败都会导致脚本退出，进而导致容器停止。

## 详细分析

### 1. Git 克隆失败
```
Cloning into '/opt/modules/ambari3'...
remote: Enumerating objects: 740973, done.
error: RPC failed; result=18, HTTP code = 200
fatal: The remote end hung up unexpectedly
fatal: early EOF
fatal: index-pack failed
```

### 2. 路径不匹配问题
- 脚本克隆到: `/opt/modules/ambari3`
- 构建脚本期望: `/opt/modules/ambari`

### 3. 缺少 patch 命令
```
/scripts/build/ambari/build.sh: line 50: patch: command not found
```

## 解决方案

### 已实施的修复

#### 1. 修改 `scripts/system/init/setup_github_code.sh`
- 使用 `--depth 1` 浅克隆减少下载量
- Git 克隆失败时不退出容器（使用 `|| { ... }` 捕获错误）
- 检查目录是否为空，避免重复克隆
- 自动创建符号链接解决路径不匹配问题

#### 2. 修改 `scripts/system/init/init_env.sh`
- 在 CentOS 7 初始化时添加 `patch` 包安装

#### 3. 更新 `jenkins-prepare-build-env.sh`
- 自动检测并修复 ambari/ambari3 路径问题
- 验证 patch 命令是否安装
- 提供手动克隆代码的指导

## 使用指南

### 方式 1: 重启容器（推荐）
```bash
# 停止并删除旧容器
docker-compose down

# 重新启动（会应用新的修复）
docker-compose up -d

# 查看启动日志
docker logs -f centos1
```

### 方式 2: 手动修复现有容器
```bash
# 启动容器
docker start centos1

# 安装 patch 命令
docker exec centos1 yum install -y patch

# 手动克隆代码（如果需要）
docker exec centos1 bash -c "
  cd /opt/modules
  git clone --depth 1 -b branch-3.0.0 https://github.com/apache/ambari.git ambari3
  ln -sf /opt/modules/ambari3 /opt/modules/ambari
"
```

### 方式 3: 使用准备脚本
```bash
# 运行环境准备脚本
./jenkins-prepare-build-env.sh
```

## 验证修复

### 检查容器状态
```bash
docker ps -a | grep centos1
```
应该显示 `Up` 状态，而不是 `Exited`

### 检查日志
```bash
docker logs centos1 --tail 50
```
应该看到 "SETUP GITHUB_CODE_DOWNLOAD end" 而不是 git 错误

### 检查目录结构
```bash
docker exec centos1 ls -la /opt/modules/
```
应该看到 ambari 或 ambari3 目录

### 检查 patch 命令
```bash
docker exec centos1 which patch
```
应该返回 `/usr/bin/patch`

## 预防措施

### 1. 离线代码包
如果网络不稳定，建议提前准备代码压缩包：
```bash
# 在宿主机准备代码包
tar -czf ambari-3.0.0.tar.gz ambari/

# 复制到容器
docker cp ambari-3.0.0.tar.gz centos1:/opt/modules/

# 在容器内解压
docker exec centos1 bash -c "
  cd /opt/modules
  tar -xzf ambari-3.0.0.tar.gz
  mv ambari ambari3
  ln -sf ambari3 ambari
"
```

### 2. 使用国内镜像
脚本已配置使用 `ghfast.top` 加速，如果仍然失败，可以考虑：
- Gitee 镜像
- 本地 Git 服务器
- 直接使用压缩包

### 3. 调整超时设置
```bash
docker exec centos1 bash -c "
  git config --global http.postBuffer 524288000
  git config --global http.lowSpeedLimit 0
  git config --global http.lowSpeedTime 999999
"
```

## 常见问题

### Q: 容器一直重启
A: 检查 docker-compose.yaml 中的 restart 策略，临时调试时可以设置为 `no`

### Q: Git 克隆速度很慢
A: 使用 `--depth 1` 浅克隆，或者使用离线代码包

### Q: 符号链接不生效
A: 确保先删除旧的目录：`docker exec centos1 rm -rf /opt/modules/ambari`

## 相关文件

- `scripts/system/init/setup_github_code.sh` - Git 克隆脚本
- `scripts/system/init/init_env.sh` - 系统初始化脚本
- `scripts/build/ambari/build.sh` - Ambari 构建脚本
- `jenkins-prepare-build-env.sh` - Jenkins 环境准备脚本
- `docker-compose.yaml` - 容器配置文件

## 更新日志

- 2026-02-26: 修复 Git 克隆失败导致容器停止的问题
- 2026-02-26: 添加 patch 命令安装
- 2026-02-26: 修复 ambari/ambari3 路径不匹配问题
