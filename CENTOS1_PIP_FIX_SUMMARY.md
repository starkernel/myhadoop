# CentOS1 容器 Pip 安装问题修复总结

## 问题
centos1 环境在安装 Python 虚拟环境时异常退出，错误信息：
```
ERROR: Could not install packages due to an EnvironmentError: Missing dependencies for SOCKS support.
```

## 根本原因
1. 容器配置了 SOCKS5 代理：`HTTP_PROXY=socks5://172.17.0.1:1080`
2. pip 需要 `PySocks` 包才能通过 SOCKS5 代理下载
3. 但安装 PySocks 本身也需要 SOCKS5 支持（循环依赖）

## 解决方案
在 pip 安装命令中添加回退逻辑：
1. 首先尝试使用代理安装 PySocks
2. 如果失败，临时禁用代理重试
3. PySocks 安装成功后，再安装其他包（如 virtualenv）

## 已修复的文件
1. `scripts/system/init/setup_virtual_env.sh` - CentOS 7
2. `scripts/system/init/ubuntu2204/setup_virtual_env.sh` - Ubuntu 22.04
3. `scripts/system/init/kylin10/setup_virtual_env.sh` - Kylin V10

## 修复代码示例
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

## 验证修复
重启容器并查看日志：
```bash
docker-compose restart centos1
docker logs -f centos1
```

应该看到成功安装的输出：
```
Successfully installed PySocks-1.7.1
Successfully installed virtualenv-20.x.x
```

## 相关文档
- [PIP_SOCKS_PROXY_FIX.md](PIP_SOCKS_PROXY_FIX.md) - 详细的问题分析和解决方案
- [CONTAINER_INIT_ISSUES.md](CONTAINER_INIT_ISSUES.md) - 容器初始化常见问题（已更新）
- [PROXY_CONFIGURATION.md](PROXY_CONFIGURATION.md) - 代理配置指南

## 修复日期
2026-02-27
