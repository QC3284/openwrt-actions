# File: gitcj.py — 从 giturl.txt 批量安全克隆 git 仓库
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions

import subprocess
import os
import re

# 安全地克隆 git 仓库 (不使用 shell=True，防止命令注入)
def git_clone(url, depth=1):
    if not re.match(r'^https://[a-zA-Z0-9._/\-:@]+$', url):
        print(f"警告: 不安全的 URL 格式，已跳过: {url}")
        return False
    cmd = ["git", "clone", "--depth", str(depth), url]
    try:
        subprocess.run(cmd, check=True)
        return True
    except subprocess.CalledProcessError:
        return False

# 读取 giturl.txt 中的链接并安全克隆仓库
def clone_repositories(file_path):
    if not os.path.isfile(file_path):
        print(f"文件不存在: {file_path}")
        return
    try:
        with open(file_path, 'r') as f:
            for line in f:
                url = line.strip()
                if url and not url.startswith('#'):
                    ok = git_clone(url)
                    if not ok:
                        print(f"克隆失败 (已跳过): {url}")
    except Exception as e:
        print(f"读取文件出错: {e}")

if __name__ == "__main__":
    clone_repositories("giturl.txt")

    import time
    time.sleep(3)

    script_path = os.path.realpath(__file__)
    giturl_path = os.path.join(os.path.dirname(script_path), "giturl.txt")

    for path in (script_path, giturl_path):
        try:
            os.remove(path)
            print(f"已删除: {path}")
        except FileNotFoundError:
            pass
        except Exception as e:
            print(f"删除失败: {path} - {e}")
