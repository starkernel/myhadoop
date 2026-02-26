# Release Notes - v1.1.0

**发布日期**: 2026-02-26  
**GitHub 仓库**: https://github.com/starkernel/myhadoop.git  
**标签**: v1.1.0

---

## 🎉 主要更新

### 1. Nexus 容器健康检查优化
- ✅ 从基于文件检查改为 HTTP 健康检查
- ✅ 增加启动等待时间（start_period: 120s）
- ✅ 增加重试次数（retries: 20）
- ✅ 修复权限问题（nexus-data 目录权限 200:200）

**影响**: Nexus 容器现在可以可靠启动，健康检查准确反映服务状态

### 2. 移除 .lock 文件依赖
- ✅ 所有脚本改用 Docker 容器名称 `nexus` 获取 IP
- ✅ 兼容旧的 .lock 文件方式（向后兼容）
- ✅ 修改了 18 个脚本文件

**修改的脚本**:
```
scripts/system/init/init_env.sh
scripts/system/init/ubuntu2204/init_env.sh
scripts/system/before/nexus/add_proxy.sh
scripts/system/before/maven/load_settings.sh
scripts/system/before/gradle/load_settings.sh
scripts/build/bigtop/build_bigtop_all.sh
scripts/build/bigtop3/el7/build_bigtop_all.sh
scripts/build/bigtop3/el8/build_bigtop_all.sh
scripts/build/bigtop3/ky10-x86/build_bigtop_all.sh
scripts/build/bigtop3/ub2204/build_bigtop_all.sh
```

**影响**: 容器启动更加稳定，不再依赖文件系统状态

### 3. MariaDB 仓库配置
- ✅ 配置 Nexus 中的 MariaDB 代理仓库
- ✅ 修复客户端仓库路径配置
- ✅ 添加自动化配置脚本 `fix-mariadb-repo.sh`

**仓库信息**:
- 仓库名称: yum-aliyun-mariadb
- 远程 URL: https://mirrors.aliyun.com/mariadb/yum/10.11/centos7-amd64/
- Nexus URL: http://nexus:8081/repository/yum-aliyun-mariadb/

**影响**: CentOS 容器可以正常安装 MariaDB 相关软件包

### 4. Docker CE 仓库处理
- ✅ 删除 docker-ce.repo 配置文件
- ✅ 在初始化脚本中自动清理 docker-ce 仓库

**影响**: 避免外网访问失败导致的容器启动问题

### 5. Jenkins 集成
- ✅ 创建优化的构建脚本 `jenkins-build.sh`
- ✅ 添加完整的配置文档
- ✅ 自动化容器状态检查

**新增文件**:
- `jenkins-build.sh` - 自动化构建脚本
- `JENKINS_SETUP.md` - 完整配置指南
- `README_JENKINS.md` - 快速参考
- `MARIADB_REPO_FIX.md` - MariaDB 配置文档

**影响**: Jenkins 任务可以成功执行，构建过程自动化

---

## 📊 测试结果

### 容器启动测试
```bash
✓ Nexus 容器运行中 (健康状态: healthy)
✓ CentOS1 容器运行中
✓ 所有服务正常运行
```

### Jenkins 构建测试
```bash
✓ 构建脚本执行成功
✓ 容器状态检查通过
✓ 构建时间: ~2 分钟
```

### 仓库访问测试
```bash
✓ YUM 仓库可访问
✓ MariaDB 仓库可访问
✓ Maven 仓库可访问
✓ Gradle 仓库可访问
```

---

## 🔧 升级指南

### 从旧版本升级

1. **拉取最新代码**
   ```bash
   cd /opt/hadoop/ambari-env
   git pull origin master
   ```

2. **修复 Nexus 数据目录权限**
   ```bash
   chown -R 200:200 common/data/nexus-data/
   ```

3. **重启容器**
   ```bash
   docker-compose down
   docker-compose up -d centos1
   ```

4. **配置 MariaDB 仓库**（如果需要）
   ```bash
   ./fix-mariadb-repo.sh
   ```

5. **更新 Jenkins 任务**
   - 使用新的构建脚本 `jenkins-build.sh`
   - 或参考 `JENKINS_SETUP.md` 更新配置

---

## 📝 配置变更

### docker-compose.yaml
```yaml
# Nexus 健康检查
healthcheck:
  test: [ "CMD-SHELL", "curl -f http://localhost:8081/ || exit 1" ]
  interval: 30s
  timeout: 10s
  retries: 20
  start_period: 120s
```

### 脚本中的 Nexus IP 获取
```bash
# 旧方式
NEXUS_IP=$(cat /scripts/system/before/nexus/.lock)

# 新方式
NEXUS_IP="nexus"  # 使用 Docker 容器名
if [ -f "/scripts/system/before/nexus/.lock" ]; then
    NEXUS_IP=$(cat /scripts/system/before/nexus/.lock)  # 向后兼容
fi
```

---

## 🐛 已知问题

无重大已知问题。

---

## 📚 文档

- **JENKINS_SETUP.md** - Jenkins 完整配置指南
- **README_JENKINS.md** - Jenkins 配置总结
- **MARIADB_REPO_FIX.md** - MariaDB 仓库配置说明
- **README.md** - 项目主文档

---

## 🙏 致谢

感谢所有贡献者和测试人员！

---

## 📞 支持

如有问题，请在 GitHub 上提交 Issue:
https://github.com/starkernel/myhadoop/issues

---

**完整变更日志**: https://github.com/starkernel/myhadoop/compare/v1.0.0...v1.1.0
