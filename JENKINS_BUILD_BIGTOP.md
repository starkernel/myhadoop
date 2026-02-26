# Jenkins 构建 Bigtop 指南

## 前提条件

1. Docker 和 Docker Compose 已安装
2. Jenkins 已安装并运行
3. 项目代码已克隆到服务器

## Jenkins 任务配置

### 创建新任务

1. 打开 Jenkins: http://localhost:8080
2. 点击 "新建任务"
3. 输入任务名称: `hadoop-ambari-bigtop-build`
4. 选择 "构建一个自由风格的软件项目"
5. 点击 "确定"

### 配置构建步骤

#### 步骤 1: 准备构建环境

在 "构建" 部分，添加 "Execute shell"：

```bash
#!/bin/bash
cd /opt/hadoop/ambari-env/
./jenkins-prepare-build-env.sh
```

#### 步骤 2: 执行 Bigtop 构建

添加另一个 "Execute shell"：

```bash
#!/bin/bash
cd /opt/hadoop/ambari-env/
./jenkins-build-bigtop.sh
```

## 重要说明

### Docker Exec 环境变量问题

容器启动时，环境变量（JAVA_HOME, MAVEN_HOME 等）被设置在 `/etc/profile` 中。但是 `docker exec` 默认启动的是非登录 shell，不会自动加载 `/etc/profile`。

**错误示例**:
```bash
# 这样会找不到 mvn 命令
docker exec centos1 bash /scripts/build/onekey_build.sh
```

**正确示例**:
```bash
# 使用 -l 参数启动登录 shell
docker exec centos1 bash -l /scripts/build/onekey_build.sh
```

### 不要使用 -it 参数

在 Jenkins 中执行 docker exec 时，不要使用 `-it` 参数：

**错误**:
```bash
docker exec -it centos1 bash /scripts/build/onekey_build.sh
# 错误: the input device is not a TTY
```

**正确**:
```bash
docker exec centos1 bash -l /scripts/build/onekey_build.sh
```

## 构建脚本说明

### jenkins-prepare-build-env.sh

功能：
- 检查容器状态
- 安装必要的构建工具（patch, git 等）
- 验证 Ambari 源码目录
- 检查并修复路径问题（ambari/ambari3）
- 验证 Java, Maven, Patch 等工具

### jenkins-build-bigtop.sh

功能：
- 检查容器运行状态
- 验证构建脚本存在
- 使用登录 shell 执行构建（自动加载环境变量）
- 返回构建结果

## 手动执行

如果不使用 Jenkins，可以手动执行：

```bash
# 进入项目目录
cd /opt/hadoop/ambari-env/

# 准备环境
./jenkins-prepare-build-env.sh

# 执行构建
./jenkins-build-bigtop.sh
```

## 故障排查

### 问题 1: mvn: command not found

**原因**: docker exec 没有使用登录 shell，环境变量未加载

**解决**: 使用 `bash -l` 参数
```bash
docker exec centos1 bash -l -c "mvn -version"
```

### 问题 2: patch: command not found

**原因**: 容器中未安装 patch 命令

**解决**: 运行准备脚本
```bash
./jenkins-prepare-build-env.sh
```

或手动安装：
```bash
docker exec centos1 yum install -y patch
```

### 问题 3: /opt/modules/ambari: No such file or directory

**原因**: 路径不匹配，代码克隆到 ambari3 但构建脚本期望 ambari

**解决**: 运行准备脚本会自动创建符号链接
```bash
docker exec centos1 ln -sf /opt/modules/ambari3 /opt/modules/ambari
```

### 问题 4: 容器未运行

**原因**: centos1 容器停止了

**解决**: 启动容器
```bash
docker-compose up -d centos1
```

## 环境变量说明

容器启动时，以下环境变量会被设置在 `/etc/profile`：

```bash
export JAVA_HOME=/opt/modules/jdk1.8.0_202
export MAVEN_HOME=/opt/modules/apache-maven-3.8.4
export GRADLE_HOME=/opt/modules/gradle-5.6.4
export ANT_HOME=/opt/modules/apache-ant-1.10.12
export IVY_HOME=/opt/modules/apache-ivy-2.5.0
export PATH=$MAVEN_HOME/bin:$GRADLE_HOME/bin:$ANT_HOME/bin:$IVY_HOME/bin:$JAVA_HOME/bin:$PATH
```

使用 `docker exec` 时：
- `bash` - 非登录 shell，不加载 /etc/profile
- `bash -l` - 登录 shell，自动加载 /etc/profile ✅

## 构建输出

构建成功后，RPM 包会生成在：
- 容器内: `/data/rpm-package/`
- 宿主机: `./common/data/rpm-package/`

## 相关文档

- [JENKINS_SETUP.md](JENKINS_SETUP.md) - Jenkins 安装和配置
- [CONTAINER_TROUBLESHOOTING.md](CONTAINER_TROUBLESHOOTING.md) - 容器故障排查
- [README_JENKINS.md](README_JENKINS.md) - Jenkins 使用说明

## 更新日志

- 2026-02-26: 修复 docker exec 环境变量问题，使用 bash -l 登录 shell
- 2026-02-26: 添加环境变量加载说明
- 2026-02-26: 初始版本
