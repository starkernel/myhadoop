# 容器初始化常见问题

## 问题 1: 容器反复停止

### 症状
- 容器启动后几分钟就停止
- 退出码: 2, 8, 128 等

### 常见原因

#### 1. 下载文件损坏
**现象**: 
```
gzip: stdin: unexpected end of file
tar: Child returned status 1
tar: Error is not recoverable: exiting now
```

**原因**: 
- 网络中断导致下载不完整
- 代理配置问题
- wget 不支持 SOCKS5 代理（需要 1.18+，CentOS 7 自带 1.14）

**解决方案**:
- 已修改为使用 curl（支持 SOCKS5）
- 解压失败时自动删除并重新下载
- 检查文件是否为空（0 字节）

#### 2. Git 克隆失败
**现象**:
```
fatal: The remote end hung up unexpectedly
fatal: early EOF
fatal: index-pack failed
```

**原因**:
- Ambari 仓库很大（740K 对象）
- 网络超时

**解决方案**:
- 使用 `--depth 1` 浅克隆
- Git 克隆失败不退出容器
- 配置 Git 使用代理

#### 3. yum 锁定冲突
**现象**:
```
Another app is currently holding the yum lock
```

**原因**:
- 容器启动脚本正在运行 yum
- Jenkins 任务同时尝试使用 yum

**解决方案**:
- Jenkins 准备脚本等待 yum 进程结束
- 最多等待 10 分钟

## 问题 2: 下载速度慢

### 原因
- 未配置代理
- 代理配置不正确
- wget 不支持 SOCKS5

### 解决方案

#### 1. 确认代理配置
```bash
docker exec centos1 env | grep -i proxy
```

应该显示:
```
HTTP_PROXY=socks5://172.17.0.1:1080
HTTPS_PROXY=socks5://172.17.0.1:1080
```

#### 2. 测试代理连接
```bash
docker exec centos1 curl -I --proxy socks5://172.17.0.1:1080 https://github.com
```

#### 3. 配置 Git 代理
```bash
docker exec centos1 bash -c "
  git config --global http.proxy socks5://172.17.0.1:1080
  git config --global https.proxy socks5://172.17.0.1:1080
"
```

## 问题 3: 容器初始化时间过长

### 正常初始化时间
- **有代理**: 5-10 分钟
- **无代理**: 10-20 分钟

### 需要下载的组件
1. JDK 8 (~195MB)
2. OpenJDK 17 (~180MB)
3. Maven (~9MB)
4. Gradle (~94MB)
5. Ant (~4MB)
6. Ivy (~1MB)
7. Ambari 源码 (Git 克隆)
8. Python 依赖
9. R 环境

### 检查初始化进度
```bash
./check-container-ready.sh
```

或查看日志:
```bash
docker logs centos1 2>&1 | grep "##.*end"
```

## 问题 4: 容器初始化完成标志

### 如何判断初始化完成

#### 方式 1: 检查 SSH 服务
```bash
docker exec centos1 pgrep -x sshd
```
有输出表示初始化完成

#### 方式 2: 查看日志最后一行
```bash
docker logs centos1 2>&1 | tail -1
```
应该显示: `sshd start over!!!!`

#### 方式 3: 使用检查脚本
```bash
./check-container-ready.sh
```

## 问题 5: 手动修复损坏的下载

### 删除损坏的文件
```bash
docker exec centos1 bash -c "
  rm -f /opt/modules/apache-ant-1.10.12-bin.tar.gz
  rm -f /opt/modules/apache-ivy-2.5.0-bin.tar.gz
  rm -f /opt/modules/jdk-8u202-linux-x64.tar.gz
  rm -f /opt/modules/openjdk-17.0.2_linux-x64_bin.tar.gz
"
```

### 重启容器
```bash
docker-compose restart centos1
```

## 问题 6: 跳过某些组件

如果某些组件不需要，可以注释掉 `scripts/master.sh` 中的相应行：

```bash
# 例如跳过 R 环境
# source /scripts/system/init/setup_r_env.sh
```

## 最佳实践

### 1. 首次启动
```bash
# 启动容器
docker-compose up -d centos1

# 监控初始化进度
watch -n 10 './check-container-ready.sh'

# 或查看实时日志
docker logs -f centos1
```

### 2. Jenkins 构建
等容器完全初始化后再运行构建任务，或者使用准备脚本（会自动等待）:
```bash
./jenkins-prepare-build-env.sh
```

### 3. 加速初始化
- 配置代理（已配置）
- 使用国内镜像源（已配置华为云）
- 预先下载文件到宿主机，然后挂载到容器

## 故障排查命令

```bash
# 查看容器状态
docker ps -a | grep centos1

# 查看退出码
docker inspect centos1 --format='{{.State.ExitCode}}'

# 查看完整日志
docker logs centos1 2>&1 | less

# 查看最近的错误
docker logs centos1 2>&1 | grep -i error

# 查看正在运行的进程
docker exec centos1 ps aux

# 查看下载进度
docker exec centos1 ls -lh /opt/modules/

# 进入容器调试
docker exec -it centos1 bash
```

## 相关文档

- [CONTAINER_TROUBLESHOOTING.md](CONTAINER_TROUBLESHOOTING.md) - 容器故障排查
- [PROXY_CONFIGURATION.md](PROXY_CONFIGURATION.md) - 代理配置
- [check-container-ready.sh](check-container-ready.sh) - 容器就绪检查脚本

## 更新日志

- 2026-02-26: 修复 wget 不支持 SOCKS5 问题，改用 curl
- 2026-02-26: 添加解压失败自动重新下载逻辑
- 2026-02-26: 添加容器就绪检查脚本
