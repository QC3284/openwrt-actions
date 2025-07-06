import subprocess
import os

# 定义一个函数来执行shell命令
def run_command(command):
    try:
        subprocess.run(command, check=True, shell=True)
    except subprocess.CalledProcessError as e:
        print(f"An error occurred: {e}")

# 读取giturl.txt文件中的链接并克隆仓库
def clone_repositories(file_path):
    try:
        with open(file_path, 'r') as file:
            for line in file:
                # 去除行尾的换行符并执行git clone命令
                repo_url = line.strip()
                if repo_url:
                    run_command(f"git clone {repo_url}")
    except FileNotFoundError:
        print(f"The file {file_path} was not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

# 等待3秒的函数
def sleep(seconds):
    import time
    time.sleep(seconds)

# 删除文件的函数
def delete_file(file_path):
    try:
        os.remove(file_path)
        print(f"File {file_path} has been deleted successfully.")
    except FileNotFoundError:
        print(f"The file {file_path} was not found.")
    except Exception as e:
        print(f"Failed to delete the file {file_path}: {e}")

# 主程序
if __name__ == "__main__":
    # 克隆GitHub仓库
    clone_repositories("giturl.txt")
    
    # 等待3秒
    sleep(3)

    # 获取当前脚本的路径和giturl.txt的路径
    script_path = os.path.realpath(__file__)
    giturl_path = os.path.join(os.path.dirname(script_path), "giturl.txt")

    # 删除脚本和giturl.txt文件
    delete_file(script_path)
    delete_file(giturl_path)