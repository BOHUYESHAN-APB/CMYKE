#!/usr/bin/env python3
"""
Echo 测试脚本 - 将输入内容原样返回喵！
"""
import sys
import json

def main():
    # 读取参数
    if len(sys.argv) > 1:
        message = sys.argv[1]
    else:
        # 尝试从 stdin 读取 JSON
        try:
            data = json.load(sys.stdin)
            message = data.get("message", "喵？")
        except:
            message = "喵？"
    
    print(f"🔊 Echo: {message}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
