"""
import os
import sys
import subprocess

def execute(cmd:list, raise_on_fail:bool = True):
    result = subprocess.run(cmd, capture_output = True, text = True, encoding = "utf-8")
    if raise_on_fail and result.returncode != 0:
        raise RuntimeError(f"Run cmd return non-zero, cmd: {str(cmd)} stdout: {result.stdout} stderr: {result.stderr}")
    return result

def patch(filename:str):
    execute(["patchelf", "--set-interpreter", "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1", filename])
    execute(["patchelf", "--add-rpath", "/data/data/com.termux/files/usr/glibc/lib", filename])

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "."
    path = path if path.endswith("/") else path + "/"
    for _ in os.listdir(path):
        if not _.startswith("."):
            patch(path + _)
            print(f"Patched {_}")
        
这些是我自己做的简陋程序，下面的是ai完善的
"""

#!/usr/bin/env python3
import os
import sys
import subprocess
import argparse
from pathlib import Path
from typing import List, Optional


class PatchError(RuntimeError):
    """自定义补丁错误异常"""
    pass


def execute(cmd: List[str], raise_on_fail: bool = True, timeout: Optional[int] = 30) -> subprocess.CompletedProcess:
    """
    执行 shell 命令
    
    Args:
        cmd: 命令及其参数列表
        raise_on_fail: 失败时是否抛出异常
        timeout: 超时时间（秒）
    
    Returns:
        subprocess.CompletedProcess: 命令执行结果
    
    Raises:
        PatchError: 当命令执行失败且 raise_on_fail=True 时
    """
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=timeout,
            check=False  # 我们自己处理返回码
        )
    except subprocess.TimeoutExpired as e:
        if raise_on_fail:
            raise PatchError(f"命令执行超时 ({timeout}s): {' '.join(cmd)}") from e
        raise
    except FileNotFoundError as e:
        if raise_on_fail:
            raise PatchError(f"命令未找到: {cmd[0]}，请确保已安装") from e
        raise

    if raise_on_fail and result.returncode != 0:
        raise PatchError(
            f"命令执行失败 (code: {result.returncode})\n"
            f"  命令: {' '.join(cmd)}\n"
            f"  标准输出: {result.stdout.strip() or '(空)'}\n"
            f"  标准错误: {result.stderr.strip() or '(空)'}"
        )
    
    return result


def is_elf_file(filepath: Path) -> bool:
    """
    检查文件是否为 ELF 格式（Linux 可执行文件/库）
    
    Args:
        filepath: 文件路径
    
    Returns:
        bool: 是否为 ELF 文件
    """
    try:
        with open(filepath, "rb") as f:
            magic = f.read(4)
            return magic == b"\x7fELF"
    except (IOError, OSError, PermissionError):
        return False


def patch_file(filepath: Path, interpreter: str, rpath: str, dry_run: bool = False, patch_rpath:bool = True) -> bool:
    """
    对单个 ELF 文件进行 patchelf 修补
    
    Args:
        filepath: 目标文件路径
        interpreter: 解释器路径
        rpath: 运行时库搜索路径
        dry_run: 是否为试运行模式（不实际执行）
    
    Returns:
        bool: 是否成功修补
    
    Raises:
        PatchError: 当修补失败时
    """
    if not filepath.is_file():
        print(f"[跳过] 不是文件: {filepath}")
        return False
    
    if not is_elf_file(filepath):
        print(f"[跳过] 非 ELF 文件: {filepath.name}")
        return False
    
    if filepath.name.endswith(".so"):
        print(f"[跳过] 非可执行文件: {filepath.name}")
        return False
    
    if dry_run:
        print(f"[预览] 将修补: {filepath}")
        return True
    
    try:
        # 设置解释器
        execute(["patchelf", "--set-interpreter", interpreter, str(filepath)])
        # 添加 rpath
        if rpath and patch_rpath:
            execute(["patchelf", "--add-rpath", rpath, str(filepath)])
        
        print(f"[成功] 已修补: {filepath.name}")
        return True
        
    except PatchError as e:
        print(f"[失败] {filepath.name}: {e}")
        raise


def patch_directory(
    directory: Path,
    interpreter: str = "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1",
    rpath: str = "/data/data/com.termux/files/usr/glibc/lib",
    recursive: bool = False,
    dry_run: bool = False,
    patch_rpath:bool = True
) -> tuple[int, int]:
    """
    批量修补目录中的 ELF 文件
    
    Args:
        directory: 目标目录
        interpreter: patchelf 解释器路径
        rpath: patchelf rpath
        recursive: 是否递归处理子目录
        dry_run: 试运行模式
    
    Returns:
        tuple[int, int]: (成功数, 跳过数)
    """
    if not directory.exists():
        raise PatchError(f"路径不存在: {directory}")
    
    if not directory.is_dir():
        raise PatchError(f"不是目录: {directory}")
    
    success_count = 0
    skip_count = 0
    
    # 选择遍历方式
    iterator = directory.rglob("*") if recursive else directory.iterdir()
    
    for item in iterator:
        # 跳过隐藏文件和目录
        if item.name.startswith("."):
            continue
        
        if item.is_dir():
            continue
            
        try:
            if patch_file(item, interpreter, rpath, dry_run, patch_rpath):
                success_count += 1
            else:
                skip_count += 1
        except PatchError:
            skip_count += 1
            continue
    
    return success_count, skip_count


def main():
    parser = argparse.ArgumentParser(
        description="批量修补 ELF 文件的 patchelf 工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s /path/to/binaries
  %(prog)s ./libs --recursive
  %(prog)s /usr/local/bin --dry-run
        """
    )
    
    parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="目标路径（文件或目录，默认为当前目录）"
    )
    parser.add_argument(
        "-i", "--interpreter",
        default="/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1",
        help="设置动态链接器解释器路径"
    )
    parser.add_argument(
        "-r", "--rpath",
        default="/data/data/com.termux/files/usr/glibc/lib",
        help="添加运行时库搜索路径(使用:分隔)"
    )
    parser.add_argument(
        "-R", "--recursive",
        action="store_true",
        help="递归处理子目录"
    )
    parser.add_argument(
        "-n", "--dry-run",
        action="store_true",
        help="试运行模式（只显示将要执行的操作）"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="显示详细信息"
    )
    
    args = parser.parse_args()
    
    target = Path(args.path).expanduser().resolve()
    
    try:
        if target.is_file():
            # 单文件模式
            patch_file(target, args.interpreter, args.rpath, args.dry_run)
        else:
            # 目录模式
            success, skipped = patch_directory(
                target,
                args.interpreter,
                args.rpath,
                args.recursive,
                args.dry_run
            )
            print(f"\n完成: 成功 {success} 个, 跳过 {skipped} 个")
            
    except KeyboardInterrupt:
        print("\n\n操作已取消")
        sys.exit(130)
    except PatchError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"未知错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
