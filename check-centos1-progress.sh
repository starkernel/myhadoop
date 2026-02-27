#!/bin/bash
# 检查 centos1 容器初始化进度

echo "=========================================="
echo "CentOS1 容器初始化进度检查"
echo "=========================================="
echo ""

# 检查容器状态
echo "1. 容器状态:"
docker ps -a | grep centos1 | awk '{print "   状态: "$7" "$8" "$9"\n   运行时间: "$10" "$11" "$12}'
echo ""

# 检查已完成的步骤
echo "2. 已完成的初始化步骤:"
docker logs centos1 2>&1 | grep "##.*end" | sed 's/.*## /   ✓ /' | tail -10
echo ""

# 检查 Python 虚拟环境
echo "3. Python 虚拟环境:"
if docker logs centos1 2>&1 | grep -q "SETUP PYTHON_VIRTUAL_ENV end"; then
    echo "   ✓ Python 虚拟环境安装完成"
    if docker logs centos1 2>&1 | grep -q "Successfully installed PySocks"; then
        echo "   ✓ PySocks 安装成功（SOCKS5 代理支持）"
    fi
    if docker logs centos1 2>&1 | grep -q "Successfully installed virtualenv"; then
        echo "   ✓ virtualenv 安装成功"
    fi
else
    echo "   ⏳ Python 虚拟环境安装中..."
fi
echo ""

# 检查 R 环境
echo "4. R 环境安装进度:"
if docker logs centos1 2>&1 | grep -q "R-4.4.2"; then
    echo "   ⏳ R 4.4.2 安装中..."
    
    # 统计已安装的推荐包
    INSTALLED=$(docker logs centos1 2>&1 | grep "DONE (" | wc -l)
    TOTAL=15
    echo "   进度: $INSTALLED/$TOTAL 个推荐包已安装"
    
    # 显示最近安装的包
    echo "   最近完成:"
    docker logs centos1 2>&1 | grep "DONE (" | tail -3 | sed 's/.*DONE (/   ✓ /' | sed 's/).*//'
    
    # 显示当前正在安装的包
    CURRENT=$(docker logs centos1 2>&1 | grep "begin installing recommended package" | tail -1 | sed 's/.*package //')
    if [ -n "$CURRENT" ]; then
        echo "   当前安装: $CURRENT"
    fi
else
    echo "   ⏸ R 环境尚未开始安装"
fi
echo ""

# 检查是否有进程在运行
echo "5. 当前活动进程:"
PROCESSES=$(docker exec centos1 ps aux 2>/dev/null | grep -E "make|gcc|R CMD" | grep -v grep | wc -l)
if [ "$PROCESSES" -gt 0 ]; then
    echo "   ✓ 有 $PROCESSES 个编译/安装进程正在运行"
    echo "   最近的进程:"
    docker exec centos1 ps aux 2>/dev/null | grep -E "make|gcc|R CMD" | grep -v grep | head -3 | awk '{print "   - "$11" "$12" "$13" "$14" "$15}'
else
    echo "   ⚠ 没有活动的编译进程"
fi
echo ""

# 检查 SSH 服务
echo "6. SSH 服务状态:"
if docker exec centos1 pgrep -x sshd >/dev/null 2>&1; then
    echo "   ✓ SSH 服务已启动 - 初始化完成！"
else
    echo "   ⏳ SSH 服务未启动 - 初始化进行中..."
fi
echo ""

# 检查最近的错误
echo "7. 最近的错误（如果有）:"
ERRORS=$(docker logs centos1 2>&1 | grep -i "error" | grep -v "ERROR_REPORTING" | tail -3)
if [ -z "$ERRORS" ]; then
    echo "   ✓ 没有发现错误"
else
    echo "$ERRORS" | sed 's/^/   ⚠ /'
fi
echo ""

echo "=========================================="
echo "提示: 使用 'docker logs -f centos1' 查看实时日志"
echo "=========================================="
