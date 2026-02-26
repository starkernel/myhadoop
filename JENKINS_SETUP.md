# Jenkins 配置指南

## 当前 Jenkins 状态
- **访问地址**: http://localhost:8080
- **Jenkins Home**: /root/.jenkins
- **运行方式**: java -jar jenkins.war
- **进程 PID**: 51606

## 一、访问 Jenkins

1. 在浏览器中打开: `http://localhost:8080` 或 `http://你的服务器IP:8080`

## 二、配置项目任务

### 方式 1: 通过 Web 界面配置（推荐）

1. **登录 Jenkins**
   - 访问 http://localhost:8080
   - 使用管理员账号登录

2. **创建新任务**
   - 点击 "新建任务" 或 "New Item"
   - 输入任务名称: `hadoop-ambari-bigtop01`
   - 选择 "Freestyle project"
   - 点击 "确定"

3. **配置源码管理**
   - 选择 "Git"
   - Repository URL: `https://github.com/starkernel/myhadoop.git`
   - Credentials: 如果是公开仓库可以留空
   - Branch: `*/master`

4. **配置构建触发器**（可选）
   - 定时构建: 例如 `H 2 * * *` (每天凌晨2点)
   - GitHub hook trigger: 如果需要 push 时自动构建

5. **配置构建步骤**
   - 点击 "增加构建步骤" → "Execute shell"
   - 输入以下脚本:
   ```bash
   cd /opt/hadoop/ambari-env/
   docker-compose -f docker-compose.yaml up -d centos1
   ```

6. **保存配置**

### 方式 2: 通过配置文件（高级）

如果你想直接编辑配置文件，可以创建或修改:
`/root/.jenkins/jobs/hadoop-ambari-bigtop01/config.xml`


## 三、现有任务配置

你的 Jenkins 任务 `hadoop-ambari-bigtop01` 已经配置好了！

**当前配置**:
- 任务名称: hadoop-ambari-bigtop01
- 任务路径: /root/.jenkins/jobs/hadoop-ambari-bigtop01/
- 构建脚本:
  ```bash
  cd /opt/hadoop/ambari-env/
  chown -R 200:200 common/data/nexus-data/
  docker-compose -f docker-compose.yaml up -d centos1 2>&1 &
  ```

**注意**: 当前配置中的 `2>&1 &` 会让命令在后台运行，这可能导致 Jenkins 无法正确跟踪构建状态。

## 四、优化建议

### 1. 修改构建脚本（推荐）

建议移除后台运行符号，让 Jenkins 能正确等待构建完成:



**方式 A: 通过 Web 界面修改**
1. 访问 http://localhost:8080
2. 点击任务 "hadoop-ambari-bigtop01"
3. 点击 "配置" 或 "Configure"
4. 找到 "构建" → "Execute shell"
5. 修改命令为:
```bash
#!/bin/bash
set -e

cd /opt/hadoop/ambari-env/

# 确保 nexus 数据目录权限正确
chown -R 200:200 common/data/nexus-data/

# 启动容器
docker-compose -f docker-compose.yaml up -d centos1

# 等待容器启动
echo "等待容器启动..."
sleep 10

# 检查容器状态
docker ps | grep centos1 && echo "✓ centos1 启动成功" || echo "✗ centos1 启动失败"
docker ps | grep nexus && echo "✓ nexus 启动成功" || echo "✗ nexus 启动失败"
```

**方式 B: 通过命令行修改**
```bash
# 备份原配置
cp ~/.jenkins/jobs/hadoop-ambari-bigtop01/config.xml ~/.jenkins/jobs/hadoop-ambari-bigtop01/config.xml.bak

# 编辑配置文件
vi ~/.jenkins/jobs/hadoop-ambari-bigtop01/config.xml
```

### 2. 添加构建后操作

可以添加邮件通知或其他后续操作：
- 构建成功/失败时发送邮件
- 清理旧的容器和镜像
- 运行测试脚本

### 3. 配置 Git 源码管理（如果需要）

如果希望 Jenkins 自动拉取最新代码：

1. 在任务配置中，找到 "源码管理"
2. 选择 "Git"
3. 填写:
   - Repository URL: `https://github.com/starkernel/myhadoop.git`
   - Branch: `*/master`
4. 在构建脚本前，代码会自动拉取到工作空间

### 4. 配置构建触发器

**定时构建**:
- 在 "构建触发器" 中选择 "定时构建"
- 输入 cron 表达式，例如:
  - `H 2 * * *` - 每天凌晨2点
  - `H/15 * * * *` - 每15分钟
  - `H 0 * * 1-5` - 工作日午夜

**GitHub Webhook**:
1. 在 Jenkins 中安装 "GitHub Plugin"
2. 在任务配置中选择 "GitHub hook trigger for GITScm polling"
3. 在 GitHub 仓库设置中添加 Webhook:
   - URL: `http://你的Jenkins地址:8080/github-webhook/`
   - Content type: `application/json`
   - 选择 "Just the push event"

## 五、常用 Jenkins 操作

### 手动触发构建
```bash
# 通过 Web 界面
访问 http://localhost:8080/job/hadoop-ambari-bigtop01/
点击 "立即构建" 或 "Build Now"

# 通过 CLI（需要配置 API Token）
curl -X POST http://localhost:8080/job/hadoop-ambari-bigtop01/build
```

### 查看构建日志
```bash
# 查看最新构建日志
cat ~/.jenkins/jobs/hadoop-ambari-bigtop01/builds/lastBuild/log

# 或通过 Web 界面
访问 http://localhost:8080/job/hadoop-ambari-bigtop01/lastBuild/console
```

### 重启 Jenkins
```bash
# 找到 Jenkins 进程
ps aux | grep jenkins.war

# 优雅重启（通过 Web）
访问 http://localhost:8080/restart

# 或者杀掉进程重新启动
kill 51606
nohup java -jar jenkins.war > /dev/null 2>&1 &
```

## 六、故障排查

### 问题 1: 构建一直等待
**原因**: 命令中有 `&` 导致后台运行
**解决**: 移除构建脚本中的 `2>&1 &`

### 问题 2: Nexus 容器不健康
**原因**: 权限问题或启动时间不够
**解决**: 
```bash
# 手动修复权限
chown -R 200:200 /opt/hadoop/ambari-env/common/data/nexus-data/

# 检查容器日志
docker logs nexus

# 检查健康状态
docker inspect nexus --format='{{.State.Health.Status}}'
```

### 问题 3: Docker 权限问题
**原因**: Jenkins 用户没有 Docker 权限
**解决**:
```bash
# 将 jenkins 用户添加到 docker 组（如果 Jenkins 以 jenkins 用户运行）
usermod -aG docker jenkins

# 或者确保以 root 运行（当前配置）
ps aux | grep jenkins
```

## 七、安全建议

1. **修改默认端口**（可选）
   ```bash
   # 停止 Jenkins
   kill 51606
   
   # 使用不同端口启动
   nohup java -jar jenkins.war --httpPort=9090 > /dev/null 2>&1 &
   ```

2. **配置防火墙**
   ```bash
   # 只允许特定 IP 访问
   firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="你的IP" port protocol="tcp" port="8080" accept'
   firewall-cmd --reload
   ```

3. **启用 HTTPS**（生产环境推荐）
   - 配置反向代理（Nginx/Apache）
   - 使用 Let's Encrypt 证书

4. **定期备份**
   ```bash
   # 备份 Jenkins 配置
   tar -czf jenkins-backup-$(date +%Y%m%d).tar.gz ~/.jenkins/
   ```

## 八、下一步

1. ✅ Jenkins 已安装并运行
2. ✅ 任务已配置
3. ✅ Nexus 权限已修复
4. ⏭️ 建议: 优化构建脚本（移除后台运行符号）
5. ⏭️ 建议: 配置 Git 源码管理
6. ⏭️ 建议: 添加构建触发器

现在你可以通过 Web 界面或命令行触发构建了！
