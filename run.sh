#!/bin/bash

# GoldStock 启动脚本

cd "$(dirname "$0")"

# 先杀掉可能正在运行的实例
killall GoldStock 2>/dev/null
sleep 0.5

# 直接运行可执行文件（避免 open 命令的权限问题）
./GoldStock.app/Contents/MacOS/GoldStock &

echo "GoldStock 已启动"
echo "如果看不到应用，请检查菜单栏右上角"
