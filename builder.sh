ARCH=$(arch)
mkdir /files
# apk --update add curl jq openjdk21 binutils
apt-get update
apt-get install -y curl jq unzip openjdk-21-jdk binutils

# 下载 NATMap，识别对应的指令集架构
# case $ARCH in
#  x86_64) DL=x86_64;;
#  aarch64) DL=arm64;;
# esac
# curl -Lso /files/natmap https://github.com/heiher/natmap/releases/latest/download/natmap-linux-$DL

# 下载 PeerBanHelper
VER=$(curl -s https://api.github.com/repos/PBH-BTN/PeerBanHelper/releases/latest | jq -r '.tag_name' | sed 's/^v//')
curl -Lso PBH.zip https://github.com/PBH-BTN/PeerBanHelper/releases/download/v${VER}/PeerBanHelper_${VER}.zip
unzip PBH.zip -d /files
curl -Lso /files/PeerBanHelper/config.yml https://raw.githubusercontent.com/PBH-BTN/PeerBanHelper/refs/heads/master/src/main/resources/config.yml
sed -e 's/"//g' -e '/^logger:/,/^[^ ]/{/^ \+hide-finish-log:/{s/false/true/}}' -i /files/PeerBanHelper/config.yml

# 生成 PeerBanHelper 的 JRE
for JAR in $(find /files/PeerBanHelper | grep .jar); do jdeps --multi-release 21 $JAR >>/tmp/DEPS 2>/dev/null; done
DEPS=$(awk '{print$NF}' /tmp/DEPS | grep -E '^(java|jdk)\.' | sort | uniq | grep -v jdk.crypto.ec | tr '\n' ',')jdk.crypto.ec
jlink --no-header-files --no-man-pages --compress=zip-9 --strip-debug --add-modules $DEPS --output /files/PeerBanHelper/jre

# 移动 BitComet 程序目录
# mkdir /files/BitComet
# mv /root/BitCometApp/usr/* /files/BitComet

# 编译 nfqsed
# apt-get install -y git gcc libnetfilter-queue-dev make
# git clone https://github.com/rgerganov/nfqsed.git
# cd nfqsed
# make
# cp ./nfqsed /files/nfqsed

# 编译 SSLproxy
apt-get install -y git make gcc libssl-dev libevent-dev zlib1g-dev
git clone https://github.com/sonertari/SSLproxy
cd SSLproxy
export FEATURES="-DWITHOUT_MIRROR -DWITHOUT_USERAUTH"
make
cp ./src/sslproxy /files/sslproxy
