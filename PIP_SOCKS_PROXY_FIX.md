# Pip SOCKS5 代理问题修复

## 问题描述

在 centos1 容器中安装 Python 虚拟环境时，`pip3.7 install virtualenv` 命令失败，错误信息：

```
ERROR: Could not install packages due to an EnvironmentError: Missing dependencies for SOCKS support.
```

## 根本原因

1. 容器配置了 SOCKS5 代理环境变量：
   ```bash
   HTTP_PROXY=socks5://172.17.0.1:1080
   HTTPS_PROXY=socks5://172.17.0.1:1080
   ```

2. pip 尝试使用 SOCKS5 代理下载包，但缺少 `PySocks` 依赖包

3. 这是一个"鸡生蛋"问题：需要 PySocks 才能通过 SOCKS5 代理下载包，但下载 PySocks 本身也需要 SOCKS5 支持

## 解决方案

### 方案 1: 先安装 PySocks（推荐）

修改 `setup_virtual_env.sh` 脚本，在安装 virtualenv 之前先安装 PySocks：

```bash
# 先安装 PySocks 以支持 SOCKS5 代理，如果失败则临时禁用代理
pip3.7 install PySocks || {
    echo "Failed to install PySocks with proxy, trying without proxy..."
    HTTP_PROXY="" HTTPS_PROXY="" http_proxy="" https_proxy="" pip3.7 install PySocks
}

# 安装 virtualenv
pip3.7 install virtualenv || {
    echo "Failed to install virtualenv with proxy, trying without proxy..."
    HTTP_PROXY="" HTTPS_PROXY="" http_proxy="" https_proxy="" pip3.7 install virtualenv
}
```

### 方案 2: 临时禁用代理

如果不需要通过代理下载 Python 包，可以临时禁用代理：

```bash
HTTP_PROXY="" HTTPS_PROXY="" http_proxy="" https_proxy="" pip3.7 install virtualenv
```

### 方案 3: 使用 HTTP 代理而非 SOCKS5

修改 docker-compose.yaml，将 SOCKS5 代理改为 HTTP 代理（如果代理服务器支持）：

```yaml
environment:
  - HTTP_PROXY=http://172.17.0.1:8080
  - HTTPS_PROXY=http://172.17.0.1:8080
```

## 已修复的文件

1. `scripts/system/init/setup_virtual_env.sh` - CentOS 7 虚拟环境设置脚本
2. `scripts/system/init/ubuntu2204/setup_virtual_env.sh` - Ubuntu 22.04 虚拟环境设置脚本

## 修复逻辑

1. 首先尝试安装 PySocks（支持 SOCKS5 代理）
2. 如果失败，临时禁用代理环境变量重试
3. PySocks 安装成功后，再安装 virtualenv
4. 如果 virtualenv 安装失败，同样临时禁用代理重试

这种方式确保：
- 如果代理可用且正常工作，优先使用代理（加速下载）
- 如果代理有问题，自动回退到直连方式
- 不会因为代理问题导致安装失败

## 验证修复

重新运行容器初始化：

```bash
# 重启 centos1 容器
docker-compose restart centos1

# 查看日志
docker logs -f centos1
```

应该看到类似输出：

```
Collecting PySocks
  Downloading PySocks-1.7.1-py3-none-any.whl (16 kB)
Installing collected packages: PySocks
Successfully installed PySocks-1.7.1

Collecting virtualenv
  Downloading virtualenv-20.x.x-py3-none-any.whl
Installing collected packages: virtualenv
Successfully installed virtualenv-20.x.x
```

## 相关问题

### 为什么不直接禁用代理？

代理可以显著加速下载速度（特别是访问国外资源如 PyPI、GitHub）：
- 不使用代理: 100-500 KB/s
- 使用代理: 1-10 MB/s

### PySocks 是什么？

PySocks 是一个 Python SOCKS 代理客户端库，支持 SOCKS4、SOCKS5 和 HTTP 代理。pip 需要它来通过 SOCKS5 代理下载包。

### 为什么 curl/wget 可以用 SOCKS5，pip 不行？

- curl 内置 SOCKS5 支持
- wget 1.18+ 支持 SOCKS5（CentOS 7 自带 1.14 不支持）
- pip 需要额外的 PySocks 库才能支持 SOCKS5

## 其他可能遇到的代理问题

### Git 克隆失败

Git 需要单独配置 SOCKS5 代理：

```bash
git config --global http.proxy socks5://172.17.0.1:1080
git config --global https.proxy socks5://172.17.0.1:1080
```

### Maven 下载慢

Maven 需要在 settings.xml 中配置代理，或使用环境变量（已配置）。

### NPM 安装失败

NPM 需要单独配置代理：

```bash
npm config set proxy http://172.17.0.1:8080
npm config set https-proxy http://172.17.0.1:8080
```

注意：NPM 不支持 SOCKS5，需要使用 HTTP 代理。

## 参考文档

- [PROXY_CONFIGURATION.md](PROXY_CONFIGURATION.md) - 容器代理配置指南
- [PySocks 文档](https://github.com/Anorov/PySocks)
- [pip 代理配置](https://pip.pypa.io/en/stable/user_guide/#using-a-proxy-server)

## 更新日志

- 2026-02-27: 修复 pip SOCKS5 代理依赖问题，添加 PySocks 自动安装和回退逻辑
