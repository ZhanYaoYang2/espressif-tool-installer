#!/bin/bash
set -e

#=============================================
# ESP-ADF Termux 安装器 (非官方)
# 版本: 1.0
# 作者: zyy
# 适用: Termux / ZeroTermux
# 依赖: 当前目录的.py和.so
# 功能: 自动安装 IDF v5.5.2 
#=============================================

IDF_VERSION="5.5.2"

exe_dir="$(cd "$(dirname "$0")" && pwd)"

if [ -e $HOME/espressif/.esp_idf_already_installed.{IDF_VERSION} ];then
    echo "已安装esp-idf，无需重复安装"
    exit 0
fi

echo "================================================================"
echo "作者: zyy"
echo "欢迎来到 Termux ESP-IDF 安装器，IDF版本: v${VERSION}"
echo "本安装器可以将esp-idf安装到Termux上，可以使用idf.py build进行编译程序，同时支持gcc和clang工具链"
echo "暂不支持在idf_tools.py里安装qemu,openocd的功能也有待验证"
echo "================================================================"
echo ""
echo "【重要提示与免责声明】"
echo ""
echo "1. 系统变更风险"
echo "   本脚本将修改系统环境，包括但不限于："
echo "   • 卸载您当前安装的 python 包"
echo "   • 安装 python-glibc 作为替代"
echo "   • 修改 glibc 库文件链接"
echo "   • 修改 $PREFIX/etc/bash.bashrc 启动配置"
echo ""
echo "2. 使用限制"
echo "   • 至少要有 10GB 的空闲存储空间"
echo "   • 必须使用 glibc 的 Python，否则 ESP-IDF 的 Python 环境安装会失败"
echo "   • 安装后请使用 . ~/export-espidf.sh 初始化环境"
echo "   • 手动初始化前必须先运行 unset LD_PRELOAD，否则无法编译"
echo ""
echo "3. 责任声明"
echo "   本脚本按'原样'提供，作者不对以下情况负责："
echo "   • 系统环境损坏或数据丢失"
echo "   • 与其他软件包的冲突"
echo "   • 因使用本脚本导致的任何直接或间接损失"
echo "   建议操作前备份重要数据。"
echo ""
echo "4. 继续安装即表示您已阅读并同意上述条款，愿意自行承担所有风险"
echo "================================================================"
echo ""

while true; do
    read -p "是否继续安装？(y/n): " answer
    answer=${answer,,}
    case "$answer" in
        y)
            echo ""
            echo "开始安装..."
            break
            ;;
        n)
            echo "已取消安装"
            exit 0
            ;;
        *)
            echo "请输入 y 或 n"
            ;;
    esac
done

# 判断修补的文件是否存在
required_files=(
    "$exe_dir/libusb-1.0.so.0"
    "$exe_dir/libudev.so.1"
    "$exe_dir/idf_tools.py"
    "$exe_dir/patch.py"
    "$exe_dir/prepare.py"
)
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "错误: 缺少必要文件 $file"
        exit 1
    fi
done

pkg update -y
pkg uninstall python -y
pkg install glibc-repo -y
pkg install patchelf python-glibc glib-glibc cmake ninja unzip wget -y

if [ ! -f $PREFIX/glibc/lib/libc.so.bak ];then
    echo "修补glibc..."
    mv $PREFIX/glibc/lib/libc.so $PREFIX/glibc/lib/libc.so.bak
    ln -s $PREFIX/glibc/lib/libc.so.6 $PREFIX/glibc/lib/libc.so
fi
echo "unset LD_PRELOAD
export PATH=$PREFIX/glibc/bin:$PATH" > $exe_dir/tmp.sh
chmod 755 $exe_dir/tmp.sh
source $exe_dir/tmp.sh
rm $exe_dir/tmp.sh

cd $HOME
mkdir -p espressif
cd espressif
echo "下载esp-idf..."
#if [ ! -e .esp_idf_downloaded.$IDF_VERSION ];then
#    wget -c https://dl.espressif.com/github_assets/espressif/esp-idf/releases/download/v${IDF_VERSION}/esp-idf-v${IDF_VERSION}.zip
#    touch .esp_idf_downloaded.$IDF_VERSION
#fi

echo "下载并解压esp-idf..."
if [ ! -e .esp_idf_unziped.$IDF_VERSION ];then
    wget -c https://dl.espressif.com/github_assets/espressif/esp-idf/releases/download/v${IDF_VERSION}/esp-idf-v${IDF_VERSION}.zip
    unzip -q esp-idf-v${IDF_VERSION}.zip
    touch .esp_idf_unziped.$IDF_VERSION
fi

rm -f esp-idf-v${IDF_VERSION}.zip
cd esp-idf-v${IDF_VERSION}

echo "修补libusb..."
# 这俩so都来自Debian
cp $exe_dir/libusb-1.0.so.0 $PREFIX/glibc/lib
cp $exe_dir/libudev.so.1 $PREFIX/glibc/lib

echo "修补idf-tools..."
cp $exe_dir/idf_tools.py tools
cp $exe_dir/patch.py tools

# 让idf的资源下载更快(国内下载飞起来)
export IDF_GITHUB_ASSETS=dl.espressif.cn/github_assets

# 必须设置这个环境，否则会报错
unset LD_PRELOAD

if [ ! -e .esp_idf_already_installed.$IDF_VERSION ];then
    echo "开始安装esp-idf"
    bash ./install.sh
    touch .esp_idf_already_installed.$IDF_VERSION
fi

echo "修复esp-idf Python环境..."
# 复制到类似~/.espressif/python_env/idf5.5_py3.12_env/lib/python3.12/site-packages/idf_component_manager/prepare_components/prepare.py
# 的路径(不同版本的Python路径不一样)
cp $exe_dir/prepare.py $HOME/.espressif/python_env/idf*_py*_env/lib/python*/site-packages/idf_component_manager/prepare_components/prepare.py

if [ ! -e tools/.fixed_idf_py.$IDF_VERSION ];then
    echo "修复idf.py"
    sed -i '1c#!/data/data/com.termux/files/usr/glibc/bin/env python' tools/idf.py
    touch tools/.fixed_idf_py.$IDF_VERSION
fi

if [ ! -e $PREFIX/etc/.esp_idf_changed_bashrc.$IDF_VERSION ];then
    echo "更改启动文件..."
    cp $PREFIX/etc/bash.bashrc $PREFIX/etc/bash.bashrc.bak
    cat << 'EOF' >> $PREFIX/etc/bash.bashrc
# ========== IDF Env Setup Start ==========
export PATH="$PREFIX/glibc/bin:$PATH"
unset LD_PRELOAD
export IDF_GITHUB_ASSETS=dl.espressif.cn/github_assets
# 检查并确保使用 glibc 的 Python
if [ -e "$PREFIX/bin/python" ]; then
    echo "[ESP-IDF] 检测到非 glibc Python，正在卸载..."
    pkg uninstall python -y || echo "[ESP-IDF] 卸载失败或已卸载"
fi

if [ ! -f "$PREFIX/glibc/bin/python" ]; then
    echo "[ESP-IDF] 未检测到 glibc Python，正在安装..."
    pkg install python-glibc -y || {
        echo "[ESP-IDF] 安装失败!"
        exit 1
    }
fi
# ========== IDF Env Setup End ==========
EOF
    touch $PREFIX/etc/.esp_idf_changed_bashrc.$IDF_VERSION
else
    echo "bashrc已被更改，无需设置"
fi

source $PREFIX/etc/bash.bashrc

echo "echo \"如果编译出现ERROR: The \\\"path\\\" field in the manifest file，可以尝试删除 dependencies.lock 后重新编译\"
. ~/espressif/esp-idf-v$IDF_VERSION/export.sh" > ~/export-espidf.sh
echo "安装完成，可以使用 . ~/export-espidf.sh 或 . ~/espressif/esp-idf-v$IDF_VERSION/export.sh 初始化环境"
echo "请立即重启，以生效更改"

touch $HOME/espressif/.esp_idf_already_installed.$IDF_VERSION
