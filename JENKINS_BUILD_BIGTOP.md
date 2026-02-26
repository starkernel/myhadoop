# Jenkins Bigtop 构建配置

## 问题说明

### 错误信息
```
the input device is not a TTY
```

### 原因
在 Jenkins 中执行 `docker exec -it` 命令时，`-it` 参数要求交互式终端（TTY），但 Jenkins 执行环境不是 TTY。

### 错误的命令
```bash
# ❌ 错误 - 不要在 Jenkins 中使用
docker exec -it centos1 /bin/bash bash /scripts/build/onekey_build.sh
```

### 正确的命令
```bash
# ✅ 正确 - Jenkins 中使用
docker exec centos1 bash /scripts/build/onekey_build.sh
```

---

## Jenkins 任务配置

### 方式 1: 使用脚本文件（推荐）

1. **创建 Jenkins 任务**
   - 任务名称: `hadoop-ambari-bigtop02`
   - 类型: Freestyle project

2. **配置构建步骤**
   - 添加构建步骤: Execute shell
   - 命令:
   ```bash
   cd /opt/hadoop/ambari-env
   ./jenkins-build-bigtop.sh
   ```

### 方式 2: 直接写命令

在 Jenkins 的 "Execute shell" 中输入：

```bash
#!/bin/bash
set -e

echo "========================================="
echo "Bigtop 一键构建"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 检查容器状态
if ! docker ps | grep -q centos1; then
    echo "✗ centos1 容器未运行"
    exit 1
fi

echo "✓ centos1 容器运行中"

# 执行构建（注意：不使用 -it）
echo "→ 开始执行构建..."
docker exec centos1 bash /scripts/build/onekey_build.sh

echo ""
echo "========================================="
echo "✓ 构建完成！"
echo "========================================="
```

---

## docker exec 参数说明

### 常用参数

| 参数 | 说明 | Jenkins 中使用 |
|------|------|----------------|
| `-i` | 保持 STDIN 打开 | ❌ 不需要 |
| `-t` | 分配伪终端（TTY） | ❌ 不能用 |
| `-d` | 后台运行 | ⚠️ 看不到输出 |
| `-e` | 设置环境变量 | ✅ 可以用 |
| `-w` | 设置工作目录 | ✅ 可以用 |
| `-u` | 指定用户 | ✅ 可以用 |

### 使用示例

```bash
# 基本用法
docker exec centos1 bash /scripts/build/onekey_build.sh

# 设置环境变量
docker exec -e BUILD_TYPE=release centos1 bash /scripts/build/onekey_build.sh

# 指定工作目录
docker exec -w /opt/bigtop centos1 bash /scripts/build/onekey_build.sh

# 以特定用户运行
docker exec -u root centos1 bash /scripts/build/onekey_build.sh

# 使用 bash -c 执行多个命令
docker exec centos1 bash -c "cd /opt/bigtop && bash /scripts/build/onekey_build.sh"
```

---

## 完整的 Jenkins Pipeline 示例

如果使用 Jenkins Pipeline，可以这样配置：

```groovy
pipeline {
    agent any
    
    stages {
        stage('检查环境') {
            steps {
                script {
                    sh '''
                        echo "检查容器状态..."
                        docker ps | grep centos1 || exit 1
                    '''
                }
            }
        }
        
        stage('执行构建') {
            steps {
                script {
                    sh '''
                        echo "开始 Bigtop 构建..."
                        docker exec centos1 bash /scripts/build/onekey_build.sh
                    '''
                }
            }
        }
        
        stage('检查结果') {
            steps {
                script {
                    sh '''
                        echo "检查构建结果..."
                        docker exec centos1 ls -lh /opt/bigtop/output/
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo '构建成功！'
        }
        failure {
            echo '构建失败！'
        }
    }
}
```

---

## 故障排查

### 问题 1: 容器未运行
```bash
# 检查容器状态
docker ps -a | grep centos1

# 启动容器
docker-compose up -d centos1
```

### 问题 2: 脚本不存在
```bash
# 检查脚本是否存在
docker exec centos1 ls -la /scripts/build/

# 如果不存在，检查挂载
docker inspect centos1 | grep -A 10 Mounts
```

### 问题 3: 权限问题
```bash
# 检查脚本权限
docker exec centos1 ls -la /scripts/build/onekey_build.sh

# 添加执行权限
docker exec centos1 chmod +x /scripts/build/onekey_build.sh
```

### 问题 4: 查看构建日志
```bash
# 实时查看容器日志
docker logs -f centos1

# 查看最近的日志
docker logs --tail 100 centos1
```

---

## 高级用法

### 1. 带超时的构建

```bash
#!/bin/bash
# 设置超时时间（秒）
TIMEOUT=3600  # 1小时

timeout $TIMEOUT docker exec centos1 bash /scripts/build/onekey_build.sh

if [ $? -eq 124 ]; then
    echo "构建超时！"
    exit 1
fi
```

### 2. 捕获构建输出

```bash
#!/bin/bash
# 将输出保存到文件
BUILD_LOG="/tmp/bigtop-build-$(date +%Y%m%d-%H%M%S).log"

docker exec centos1 bash /scripts/build/onekey_build.sh 2>&1 | tee "$BUILD_LOG"

echo "构建日志已保存到: $BUILD_LOG"
```

### 3. 并行构建多个组件

```bash
#!/bin/bash
# 并行构建
docker exec centos1 bash -c "
    cd /opt/bigtop
    ./gradlew hadoop-pkg zookeeper-pkg hbase-pkg -Pparallel
"
```

---

## 最佳实践

1. ✅ **不使用 -it 参数** - Jenkins 中永远不要用
2. ✅ **使用 set -e** - 遇到错误立即退出
3. ✅ **添加日志输出** - 方便调试和追踪
4. ✅ **检查前置条件** - 确保容器运行、脚本存在
5. ✅ **捕获退出码** - 正确处理构建结果
6. ✅ **设置超时** - 避免构建卡死
7. ✅ **保存日志** - 便于问题排查

---

## 相关文件

- `jenkins-build-bigtop.sh` - Bigtop 构建脚本
- `jenkins-build.sh` - 容器启动脚本
- `JENKINS_SETUP.md` - Jenkins 配置指南

---

## 测试命令

```bash
# 测试脚本是否可执行
./jenkins-build-bigtop.sh

# 手动测试 docker exec
docker exec centos1 bash -c "echo 'Hello from centos1'"

# 检查构建脚本
docker exec centos1 cat /scripts/build/onekey_build.sh | head -20
```

---

**更新时间**: 2026-02-26  
**状态**: ✅ 已验证
