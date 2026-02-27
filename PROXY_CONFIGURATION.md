# 容器代理配置指南

## 概述

为了加速容器内的下载速度（Maven 依赖、NPM 包、Git 克隆等），配置容器使用宿主机的 SOCKS5 代理。

## 配置说明

### 宿主机代理地址

- 代理类型: SOCKS5
- 代理地址: `127.0.0.1:1080` (宿主机)
- 容器访问: `172.17.0.1:1080` (Docker 网桥 IP)

### 为什么使用 172.17.0.1

容器内的 `127.0.0.1` 指向容器自己，不是宿主机。要访问宿主机服务，需要使用：
- `172.17.0.1` - Docker 默认网桥 IP
- `host.docker.internal` - Docker Desktop 特有（Linux 不支持）

### 配置的环境变量

#### 1. Shell 环境变量（curl, wget, git 等）
```bash
HTTP_PROXY=socks5h://172.17.0.1:1080
HTTPS_PROXY=socks5h://172.17.0.1:1080
http_proxy=socks5h://172.17.0.1:1080
https_proxy=socks5h://172.17.0.1:1080
```

**注意**: 使用 `socks5h://` 而不是 `socks5://`，区别在于：
- `socks5://` - 客户端本地解析 DNS，然后通过代理连接
- `socks5h://` - 通过代理服务器解析 DNS（远程 DNS 解析）

在某些网络环境中，本地 DNS 解析可能被限制，使用 `socks5h://` 可以避免 DNS 解析问题。

#### 2. Java 系统属性（Maven, Gradle, Nexus）
```bash
-Dhttp.proxyHost=172.17.0.1
-Dhttp.proxyPort=1080
-Dhttps.proxyHost=172.17.0.1
-Dhttps.proxyPort=1080
```

#### 3. 不使用代理的地址（NO_PROXY）
```bash
NO_PROXY=localhost,127.0.0.1,172.20.0.0/24,nexus,centos1,centos2,centos3
```

这样容器之间的通信不会走代理，只有外网访问才使用代理。

## 已配置的容器

### Nexus 容器
- ✅ Java 系统属性代理
- ✅ 环境变量代理
- ✅ NO_PROXY 配置

### CentOS1 容器
- ✅ 环境变量代理
- ✅ NO_PROXY 配置

### 其他容器
如需配置，参考 centos1 的配置方式。

## 验证代理是否工作

### 1. 检查环境变量
```bash
docker exec centos1 bash -c "env | grep -i proxy"
```

### 2. 测试外网访问
```bash
# 测试 HTTP 请求
docker exec centos1 curl -I https://www.google.com

# 测试 Git 克隆
docker exec centos1 git clone --depth 1 https://github.com/apache/maven.git /tmp/test
```

### 3. 测试 Maven 下载
```bash
docker exec centos1 bash -l -c "mvn help:evaluate -Dexpression=project.version"
```

### 4. 查看代理日志
在宿主机查看代理软件的连接日志，应该能看到来自 `172.17.0.1` 的连接。

## 重启容器应用配置

```bash
# 重启单个容器
docker-compose up -d centos1

# 重启所有容器
docker-compose down
docker-compose up -d
```

## 故障排查

### 问题 1: 代理连接失败

**检查宿主机代理是否监听所有接口**:
```bash
# 查看代理监听地址
netstat -tlnp | grep 1080
```

应该显示 `0.0.0.0:1080` 或 `*:1080`，而不是 `127.0.0.1:1080`

**解决方案**:
修改代理软件配置，监听 `0.0.0.0:1080` 而不是 `127.0.0.1:1080`

### 问题 2: 容器间通信走了代理

**现象**: 访问 Nexus 或其他容器很慢

**原因**: NO_PROXY 配置不正确

**解决**: 确保 NO_PROXY 包含：
- 容器名称: nexus, centos1, centos2, centos3
- 内网网段: 172.20.0.0/24
- 本地地址: localhost, 127.0.0.1

### 问题 3: Maven 不使用代理

**原因**: Maven 需要在 settings.xml 中单独配置代理

**解决**: 编辑 `~/.m2/settings.xml`
```xml
<proxies>
  <proxy>
    <id>socks5-proxy</id>
    <active>true</active>
    <protocol>http</protocol>
    <host>172.17.0.1</host>
    <port>1080</port>
  </proxy>
</proxies>
```

或者使用环境变量（已配置）。

### 问题 4: Git 克隆仍然很慢

**Git 需要额外配置 SOCKS5 代理**:
```bash
docker exec centos1 bash -c "
  git config --global http.proxy socks5h://172.17.0.1:1080
  git config --global https.proxy socks5h://172.17.0.1:1080
"
```

## 性能对比

### 不使用代理
- Maven 中央仓库: 100-500 KB/s
- GitHub 克隆: 50-200 KB/s
- NPM 包下载: 100-300 KB/s

### 使用代理（取决于代理服务器）
- Maven 中央仓库: 1-10 MB/s
- GitHub 克隆: 1-5 MB/s
- NPM 包下载: 2-10 MB/s

## 安全注意事项

1. **代理认证**: 如果代理需要认证，需要在 URL 中包含用户名密码：
   ```
   socks5://username:password@172.17.0.1:1080
   ```

2. **防火墙规则**: 确保宿主机防火墙允许 Docker 网桥访问代理端口：
   ```bash
   # 允许 Docker 网桥访问代理
   iptables -A INPUT -s 172.17.0.0/16 -p tcp --dport 1080 -j ACCEPT
   ```

3. **代理日志**: 定期检查代理日志，确保没有异常连接。

## 禁用代理

如果不需要代理，注释掉 docker-compose.yaml 中的代理配置：

```yaml
# environment:
#   - HTTP_PROXY=socks5h://172.17.0.1:1080
#   - HTTPS_PROXY=socks5h://172.17.0.1:1080
```

然后重启容器：
```bash
docker-compose up -d
```

## 相关文档

- [docker-compose.yaml](docker-compose.yaml) - 容器配置文件
- [Docker 网络文档](https://docs.docker.com/network/)

## 更新日志

- 2026-02-26: 初始版本，配置 Nexus 和 CentOS1 容器代理
