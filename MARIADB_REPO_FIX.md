# MariaDB 仓库配置修复总结

## 问题描述

CentOS1 容器启动失败，原因是：
1. MariaDB 仓库路径配置错误（404 错误）
2. Docker CE 仓库连接失败（外部网络问题）

## 解决方案

### 1. 修复 MariaDB 仓库配置

**问题**: 
- 原配置路径: `http://nexus:8081/repository/yum-public/yum/10.11.10/centos7-amd64/`
- 实际 Nexus 仓库: `http://nexus:8081/repository/yum-aliyun-mariadb/`

**修复**:
```bash
# 运行修复脚本
./fix-mariadb-repo.sh
```

**修改的文件**: `scripts/system/init/init_env.sh`
```bash
[yum-public-mariadb]
name=YUM Public Repository (CentOS 7 MariaDB)
baseurl=http://$1:8081/repository/yum-aliyun-mariadb/  # 修改后
enabled=1
gpgcheck=0
```

### 2. 禁用 Docker CE 仓库

**问题**: Docker CE 仓库在容器内无法访问外网

**修复**: 在 `init_centos7()` 函数中删除 docker-ce 仓库配置
```bash
rm -rf /etc/yum.repos.d/CentOS* /etc/yum.repos.d/epel* /etc/yum.repos.d/ambari-bigtop* /etc/yum.repos.d/docker-ce*
```

## Nexus 仓库配置

### MariaDB 代理仓库
- **仓库名称**: yum-aliyun-mariadb
- **类型**: proxy (代理仓库)
- **远程 URL**: https://mirrors.aliyun.com/mariadb/yum/10.11/centos7-amd64/
- **Nexus URL**: http://localhost:8081/repository/yum-aliyun-mariadb/

### 验证仓库
```bash
# 测试 MariaDB 仓库
curl -I http://localhost:8081/repository/yum-aliyun-mariadb/repodata/repomd.xml

# 应该返回 HTTP/1.1 200 OK
```

## 测试结果

```bash
# 启动容器
docker-compose up -d centos1

# 检查状态
docker ps | grep centos1
# ✓ CentOS1 运行中

docker ps | grep nexus
# ✓ Nexus 运行中 (healthy)
```

## 修改的文件清单

1. **scripts/system/init/init_env.sh**
   - 修复 Nexus IP 获取方式（使用容器名）
   - 修复 MariaDB 仓库路径
   - 删除 Docker CE 仓库配置

2. **scripts/system/before/nexus/add_proxy.sh**
   - 移除 `.lock` 文件依赖

3. **docker-compose.yaml**
   - 优化 Nexus 健康检查（HTTP 方式）

4. **fix-mariadb-repo.sh** (新增)
   - 自动修复 MariaDB 仓库配置的脚本

## 相关命令

### 查看容器日志
```bash
docker logs centos1
docker logs nexus
```

### 进入容器
```bash
docker exec -it centos1 bash
docker exec -it nexus bash
```

### 测试 YUM 仓库
```bash
# 在 centos1 容器内
docker exec centos1 yum repolist
docker exec centos1 yum search mariadb
```

### 重启服务
```bash
# 重启所有容器
docker-compose down
docker-compose up -d centos1

# 只重启 centos1
docker restart centos1
```

## 注意事项

1. **首次启动时间**: Nexus 首次启动需要 2-5 分钟，请耐心等待
2. **权限问题**: 确保 `common/data/nexus-data/` 目录权限为 200:200
3. **网络连接**: 容器需要能访问阿里云镜像源来同步软件包
4. **仓库同步**: MariaDB 仓库首次访问时会从上游同步，可能较慢

## 下一步

1. ✅ MariaDB 仓库已配置
2. ✅ Docker CE 仓库已禁用
3. ✅ 容器启动成功
4. ⏭️ 可以继续配置其他服务（Ambari、Hadoop 等）
5. ⏭️ 提交代码到 Git 仓库

## 提交更改

```bash
cd /opt/hadoop/ambari-env
git add scripts/system/init/init_env.sh
git add fix-mariadb-repo.sh
git add MARIADB_REPO_FIX.md
git commit -m "Fix MariaDB repository configuration and disable Docker CE repo"
git push origin master
```

---

**修复完成时间**: 2026-02-26 06:48
**状态**: ✅ 所有问题已解决，容器正常运行
