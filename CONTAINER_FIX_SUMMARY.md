# 容器停止问题修复总结

## 问题描述

CentOS1 容器在启动后自动停止，退出码为 128。

## 根本原因

1. **Git 克隆失败**: 容器启动脚本尝试从 GitHub 克隆大型 Ambari 仓库（740,973 个对象），网络超时导致克隆失败
2. **脚本退出机制**: `setup_github_code.sh` 使用 `set -e`，任何命令失败都会导致脚本退出
3. **路径不匹配**: 脚本克隆到 `/opt/modules/ambari3`，但构建脚本期望 `/opt/modules/ambari`
4. **缺少依赖**: 容器中缺少 `patch` 命令，导致构建失败

## 修复方案

### 1. 修改 `scripts/system/init/setup_github_code.sh`

**关键改进**:
- 使用 `--depth 1` 浅克隆，减少下载量
- Git 克隆失败时不退出容器，使用 `|| { ... }` 捕获错误并继续
- 检查目录是否为空（不仅检查是否存在），避免重复克隆空目录
- 自动创建符号链接 `/opt/modules/ambari -> /opt/modules/ambari3`

**修改前**:
```bash
if [ -d "$TARGET_DIR" ]; then
  echo "目录已存在: $TARGET_DIR"
else
  git clone -b "$BRANCH_VERSION" "$REPO_URL" "$TARGET_DIR"
  if [ $? -eq 0 ]; then
    echo "仓库检出成功: $TARGET_DIR"
  else
    echo "仓库检出失败: $TARGET_DIR"
    exit 1  # 这里会导致容器停止
  fi
fi
```

**修改后**:
```bash
if [ -d "$TARGET_DIR" ] && [ "$(ls -A $TARGET_DIR 2>/dev/null)" ]; then
  echo "目录已存在且不为空: $TARGET_DIR，跳过克隆"
else
  git clone --depth 1 -b "$BRANCH_VERSION" "$REPO_URL" "$TARGET_DIR" || {
    echo "警告: 仓库检出失败: $TARGET_DIR (可能是网络问题，继续启动容器)"
    mkdir -p "$TARGET_DIR"
  }
fi

# 创建符号链接解决路径不匹配
if [ -d "/opt/modules/ambari3" ] && [ ! -L "/opt/modules/ambari" ]; then
  ln -sf /opt/modules/ambari3 /opt/modules/ambari
fi
```

### 2. 修改 `scripts/system/init/init_env.sh`

在 CentOS 7 初始化函数中添加 `patch` 包：

```bash
init_centos7() {
  # ... 其他代码 ...
  yum -y install centos-release-scl centos-release-scl-rh openssh-server passwd sudo net-tools unzip wget git patch || true
  # ... 其他代码 ...
}
```

### 3. 更新 `jenkins-prepare-build-env.sh`

增强环境准备脚本：
- 自动检测并修复 ambari/ambari3 路径问题
- 验证 patch 命令是否安装
- 提供手动克隆代码的详细指导
- 容器未运行时自动尝试启动

## 验证步骤

### 1. 重启容器测试
```bash
docker-compose down
docker-compose up -d
docker logs -f centos1
```

### 2. 检查容器状态
```bash
docker ps -a | grep centos1
# 应该显示 "Up" 状态
```

### 3. 验证目录结构
```bash
docker exec centos1 ls -la /opt/modules/
# 应该看到 ambari 符号链接指向 ambari3
```

### 4. 验证 patch 命令
```bash
docker exec centos1 which patch
# 应该返回 /usr/bin/patch
```

## 使用建议

### 场景 1: 网络良好
直接启动容器，脚本会自动克隆代码：
```bash
docker-compose up -d
```

### 场景 2: 网络不稳定
使用离线代码包：
```bash
# 准备代码包
tar -czf ambari-3.0.0.tar.gz /path/to/ambari/

# 复制到容器
docker cp ambari-3.0.0.tar.gz centos1:/opt/modules/

# 解压
docker exec centos1 bash -c "
  cd /opt/modules
  tar -xzf ambari-3.0.0.tar.gz
  mv ambari ambari3
  ln -sf ambari3 ambari
"
```

### 场景 3: Jenkins 构建
使用准备脚本：
```bash
./jenkins-prepare-build-env.sh
./jenkins-build-bigtop.sh
```

## 影响范围

### 修改的文件
1. `scripts/system/init/setup_github_code.sh` - Git 克隆逻辑
2. `scripts/system/init/init_env.sh` - 添加 patch 包
3. `jenkins-prepare-build-env.sh` - 增强环境检查

### 新增的文件
1. `CONTAINER_TROUBLESHOOTING.md` - 详细故障排查指南
2. `CONTAINER_FIX_SUMMARY.md` - 本文件

## 后续优化建议

1. **代码预下载**: 在构建 Docker 镜像时预先下载代码
2. **本地 Git 服务器**: 搭建内网 Git 镜像服务器
3. **健康检查优化**: 添加容器启动完成的健康检查
4. **日志增强**: 添加更详细的启动日志便于排查问题

## 相关文档

- [CONTAINER_TROUBLESHOOTING.md](CONTAINER_TROUBLESHOOTING.md) - 详细故障排查指南
- [JENKINS_BUILD_BIGTOP.md](JENKINS_BUILD_BIGTOP.md) - Jenkins 构建指南
- [JENKINS_SETUP.md](JENKINS_SETUP.md) - Jenkins 配置指南
