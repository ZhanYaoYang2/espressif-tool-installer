set -e

#=============================================
# ESP-ADF Termux 安装器 (非官方)
# 版本: 1.0
# 作者: zyy
# 适用: Termux / ZeroTermux
# 依赖: esp-adf-dev-d108801d.zip (必须与脚本同目录)
# 功能: 自动安装 IDF v5.5.2 并部署 ADF v3.0-m
#=============================================

ADF_VERSION="git-master"
IDF_VERSION="5.5.2"

exe_dir="$(cd "$(dirname "$0")" && pwd)"

if [ -e $HOME/espressif/.esp_adf_already_installed.${ADF_VERSION} ];then
    echo "已安装esp-adf，无需重复安装"
    exit 0
fi

echo "================================================================"
echo "作者: zyy"
echo "欢迎来到 Termux ESP-ADF 安装器"
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
echo "   • 包含 idf.install.v${IDF_VERSION}.sh 中可能的风险"
echo ""
echo "2. 使用限制"
echo "   • 运行此程序会自动安装esp-idf"
echo "   • 目前只能使用自带的adf"
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

pkg update -y
pkg install git -y

if [ ! -f $HOME/espressif/.esp_idf_already_installed.${IDF_VERSION} ];then
    echo "esp-idf未安装，正在安装..."
    $exe_dir/idf.install.v${IDF_VERSION}.sh
fi

if [ ! -f $exe_dir/adf_gitmodules_mirror ]; then
    echo "错误: 缺少adf_gitmodules_mirror"
    exit 1
fi

cd $HOME/espressif

if [ ! -e .esp_adf_gited.${ADF_VERSION} ];then
    echo "克隆esp-adf..."
    # 防止有没克隆完的仓库
    rm -rf esp-adf-${ADF_VERSION}
    git clone https://gitee.com/EspressifSystems/esp-adf esp-adf-${ADF_VERSION} --depth=1
    cd esp-adf-${ADF_VERSION}
    cp $exe_dir/adf_gitmodules_mirror .gitmodules
    git submodule update --init --recursive --depth=1
    touch .esp_adf_gited.${ADF_VERSION}
fi

echo "export IDF_PATH=$HOME/espressif/esp-idf-v${IDF_VERSION}
. $HOME/espressif/esp-adf-${ADF_VERSION}/export.sh" > $HOME/export-espadf.sh
echo "安装完成，可以使用 . ~/export-espadf.sh 或 export IDF_PATH=$HOME/espressif/esp-idf-v${IDF_VERSION} && . ~/espressif/esp-adf-${ADF_VERSION}/export.sh 初始化环境"

touch $HOME/espressif/.esp_adf_already_installed.${ADF_VERSION}

source $PREFIX/etc/bash.bashrc

echo "请立即重启，以生效更改"
