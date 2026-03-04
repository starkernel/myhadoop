#!/usr/bin/env python3
import sys
import re

def fix_flink_clients_pom(filepath):
    """修复 flink-clients/pom.xml - 禁用测试 assembly"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 将所有 process-test-classes 阶段改为 none
    content = content.replace(
        '<phase>process-test-classes</phase>',
        '<phase>none</phase>'
    )
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✓ 已修复 {filepath}")

def fix_flink_python_pom(filepath):
    """修复 flink-python/pom.xml - 禁用测试 jar 构建"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 找到 build-test-jars 执行块，将其 phase 改为 none
    pattern = r'(<id>build-test-jars</id>.*?)<phase>package</phase>'
    replacement = r'\1<phase>none</phase>'
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✓ 已修复 {filepath}")

if __name__ == '__main__':
    fix_flink_clients_pom('flink-clients/pom.xml')
    fix_flink_python_pom('flink-python/pom.xml')
    print("✓ 所有 POM 文件修复完成")
