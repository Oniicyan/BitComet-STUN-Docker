#!/bin/bash

# 初始化变量
[ $STUN ] && ([ $Stun ] || export Stun=$STUN)
[ $BITCOMET_WEBUI_USERNAME ] && export WEBUI_USERNAME=$BITCOMET_WEBUI_USERNAME
[ $BITCOMET_WEBUI_PASSWORD ] && export WEBUI_PASSWORD=$BITCOMET_WEBUI_PASSWORD
HOSTIP=$(awk '/32 host/{print f}{f=$2}' /proc/net/fib_trie | grep -v 127.0.0.1 | sort | uniq)

# 初始化日志函数
LOG() { tee -a /BitComet/DockerLogs.log ;}

echo 开始执行 BitComet 贴吧修改版 | tee /tmp/DockerLogs.log

# 初始化配置目录
for DIR in /BitComet /PeerBanHelper; do
	if ! mount | grep -q ' '$DIR' '; then
		echo $DIR 目录未挂载 | tee -a /tmp/DockerLogs.log
		DIR_CFG_FLAG=1
		[ -d $DIR ] || mkdir $DIR
	fi
done
mv -f /BitComet/DockerLogs.log /BitComet/DockerLogs.old 2>/dev/null
mv -f /tmp/DockerLogs.log /BitComet/DockerLogs.log
[ $DIR_CFG_FLAG ] && echo 应用程序配置及数据保存到容器层，重启后可能会丢失 | LOG

# 初始化 BitComet 配置文件
BC_CFG=/BitComet/BitComet.xml
[ -f $BC_CFG ] || {
	echo BitComet 配置文件不存在，执行初始化 | LOG
	cp /files/BitComet.xml $BC_CFG
}
grep DefaultDownloadPath $BC_CFG | grep -q /Downloads || sed 's,<Settings>,<Settings><DefaultDownloadPath>/Downloads</DefaultDownloadPath>,' -i $BC_CFG
grep EnableUPnP $BC_CFG | grep -q false || sed 's,<Settings>,<Settings><EnableUPnP>false</EnableUPnP>,' -i $BC_CFG
grep EnableTorrentShare $BC_CFG | grep -q false || sed 's,<Settings>,<Settings><EnableTorrentShare>false</EnableTorrentShare>,' -i $BC_CFG

# 初始化 BitComet 保存位置
if mount | grep -q ' /Downloads '; then
	echo /Downloads 目录已挂载 | LOG
else
	echo /Downloads 目录未挂载，默认保存位置在容器层，重启后可能会丢失 | LOG
	BC_DL_FLAG=1
fi
BC_DL_REX='/Downloads|/BitComet|/PeerBanHelper|/tmp|/etc/resolv.conf|/etc/hostname|/etc/hosts'
BC_DL_DIR=$(mount | grep -E '^/' | grep -vE ' ('$BC_DL_REX') ' | awk '{print$3}')
if [ $BC_DL_DIR ]; then
	echo 以下目录将作为 BitComet 的自定义保存位置 | LOG
	for DIR in $BC_DL_DIR; do echo $DIR | LOG; done
	sed 's,<Settings>,<Settings><DirCandidate>'$(echo $BC_DL_DIR | sed 's, /,|/,')'</DirCandidate>,' -i $BC_CFG
else
	[ $BC_DL_FLAG ] && echo 未挂载任何自定义下载目录 | LOG
fi

# 初始化 BitComet WebUI 用户名与密码
[ $WEBUI_USERNAME ] || export WEBUI_USERNAME=$(grep WebInterfaceUsername $BC_CFG | grep -oE '>.*<' | tr -d '><')
[ $WEBUI_PASSWORD ] || export WEBUI_PASSWORD=$(grep WebInterfacePassword $BC_CFG | grep -oE '>.*<' | tr -d '><')
[ "$WEBUI_USERNAME" = test ] && {
	unset WEBUI_USERNAME
	echo 禁止使用用户名 test，已清除
}
[ "$WEBUI_PASSWORD" = test ] && {
	unset WEBUI_PASSWORD
	echo 禁止使用密码 test，已清除
}
[ $WEBUI_USERNAME ] || {
	export WEBUI_USERNAME=$(base64 /proc/sys/kernel/random/uuid | cut -c -8)
	echo BitComet WebUI 用户名未指定，随机生成以下 8 位用户名 | LOG
	echo $WEBUI_USERNAME | LOG
}
[ $WEBUI_PASSWORD ] || {
	export WEBUI_PASSWORD=$(base64 /proc/sys/kernel/random/uuid | cut -c -16)
	echo BitComet WebUI 密码未指定，随机生成以下 16 位密码 | LOG
	echo $WEBUI_PASSWORD | LOG
}
>/BitComet/Secrect
echo WebInterfaceUsername: $WEBUI_USERNAME >>/BitComet/Secrect
echo WebInterfacePassword: $WEBUI_PASSWORD >>/BitComet/Secrect
echo BitComet WebUI 用户名与密码已保存至 /BitComet/Secrect | LOG

# 初始化 BitComet WebUI 端口
[ $BITCOMET_WEBUI_PORT ] || export BITCOMET_WEBUI_PORT=$(grep WebInterfacePort $BC_CFG | grep -oE '>.*<' | tr -d '><')
if [ $BITCOMET_WEBUI_PORT ]; then
	if [[ $BITCOMET_WEBUI_PORT =~ ^[0-9]+$ ]] && [ $BITCOMET_WEBUI_PORT -le 65535 ]; then
		[ $BITCOMET_WEBUI_PORT -ge 1024 ] || echo BitComet WebUI 端口指定为 1024 以下，可能无法监听 | LOG
		BC_WEBUI_PORT_ORIG=$BITCOMET_WEBUI_PORT
	else
		echo BitComet WebUI 端口指定错误，仅接受 65535 以下数字，执行初始化 | LOG
		export BITCOMET_WEBUI_PORT=8080
	fi
else
	echo BitComet WebUI 端口未指定，执行初始化 | LOG
	export BITCOMET_WEBUI_PORT=8080
fi
while (>/dev/tcp/0.0.0.0/$BITCOMET_WEBUI_PORT) 2>/dev/null || echo $BITCOMET_WEBUI_PORT | grep -qE '^'$BITCOMET_BT_PORT'$|^'$PBH_WEBUI_PORT'$' ; do
	export BITCOMET_WEBUI_PORT=$(shuf -i 1024-65535 -n 1)
	BC_WEBUI_PORT_SHUF=1
done
[ $BC_WEBUI_PORT_ORIG ] &&[ $BC_WEBUI_PORT_SHUF ] && echo BitComet WebUI 端口 $BC_WEBUI_PORT_ORIG 被占用，已重新分配 | LOG
echo BitComet WebUI 使用以下地址访问 | LOG
for IP in $HOSTIP; do echo http://$IP:$BITCOMET_WEBUI_PORT | LOG; done

# 初始化 PeerBanHelper 配置文件
PBH_CFG=/PeerBanHelper/data/config/config.yml
if [ -f $PBH_CFG ]; then
	[ $(sed -n '/^server:/,/^[^ ]/{/^ \+address:/p}' $PBH_CFG | awk -F : '{print$2}') ] || \
	echo PeerBanHelper 配置文件不正确，执行初始化 | LOG
	cp -f /files/PeerBanHelper/config.yml $PBH_CFG
else
	echo PeerBanHelper 配置文件不存在，执行初始化 | LOG
	mkdir -p /PeerBanHelper/data/config
	cp /files/PeerBanHelper/config.yml $PBH_CFG
fi

# 初始化 PeerBanHelper WebUI Token
[ $PBH_WEBUI_TOKEN ] || export PBH_WEBUI_TOKEN=$(sed -n '/^server:/,/^[^ ]/{/^ \+token:/p}' $PBH_CFG | awk -F : '{print$2}')
if [ ! $PBH_WEBUI_TOKEN ]; then
	export PBH_WEBUI_TOKEN=$(cat /proc/sys/kernel/random/uuid)
	echo PeerBanHelper WebUI Token 未指定，随机生成以下 Token | LOG
	echo $PBH_WEBUI_TOKEN | LOG
	if [ "$(sed -n '/^server:/,/^[^ ]/{/^ \+token:/p}' $PBH_CFG)" ]; then
		sed '/^server:/,/^[^ ]/{/^ \+token:/{s/token:.*/token: '$PBH_WEBUI_TOKEN'/}}' -i $PBH_CFG
	else
		PBH_TOKEN_STR=$(sed -n '/^server:/,/^[^ ]/{/^ \+address:/{s/address:.*/token: '$PBH_WEBUI_TOKEN'/p}}' $PBH_CFG)
		sed '/^server:/a\'"$PBH_TOKEN_STR"'' -i $PBH_CFG
	fi
fi
echo $PBH_WEBUI_TOKEN >/PeerBanHelper/Secrect
echo PeerBanHelper WebUI Token 已保存至 /PeerBanHelper/Secrect | LOG

# 初始化 PeerBanHelper WebUI 端口
[ $PBH_WEBUI_PORT ] || export PBH_WEBUI_PORT=$(sed -n '/^server:/,/^[^ ]/{/^ \+http:/p}' $PBH_CFG | awk -F : '{print$2}' | tr -d ' "')
if [ $PBH_WEBUI_PORT ]; then
	if [[ $PBH_WEBUI_PORT =~ ^[0-9]+$ ]] && [ $PBH_WEBUI_PORT -le 65535 ]; then
		[ $PBH_WEBUI_PORT -ge 1024 ] || echo PeerBanHelper WebUI 端口指定为 1024 以下，可能无法监听 | LOG
		PBH_PORT_ORIG=$PBH_WEBUI_PORT
	else
		echo PeerBanHelper WebUI 端口指定错误，仅接受 65535 以下数字，执行初始化 | LOG
		export PBH_WEBUI_PORT=9898
	fi
else
	echo PeerBanHelper WebUI 端口未指定，执行初始化 | LOG
	export PBH_WEBUI_PORT=9898
fi
while (>/dev/tcp/0.0.0.0/$PBH_WEBUI_PORT) 2>/dev/null || echo $PBH_WEBUI_PORT | grep -qE '^'$BITCOMET_WEBUI_PORT'$|^'$BITCOMET_BT_PORT'$' ; do
	export PBH_WEBUI_PORT=$(shuf -i 1024-65535 -n 1)
	PBH_PORT_SHUF=1
done
[ $PBH_PORT_ORIG ] && [ $PBH_PORT_SHUF ] && echo PeerBanHelper WebUI 端口 $PBH_PORT_ORIG 被占用，已重新分配 | LOG
echo PeerBanHelper WebUI 使用以下地址访问 | LOG
for IP in $HOSTIP; do echo http://$IP:$PBH_WEBUI_PORT | LOG; done
[ $PBH_WEBUI_PORT != "$PBH_PORT_ORIG" ] && \
if [ "$(sed -n '/^server:/,/^[^ ]/{/^ \+http:/p}' $PBH_CFG)" ]; then
	sed '/^server:/,/^[^ ]/{/^ \+http:/{s/http:.*/http: '$PBH_WEBUI_PORT'/}}' -i $PBH_CFG
else
	PBH_PORT_STR=$(sed -n '/^server:/,/^[^ ]/{/^ \+address:/{s/address:.*/http: '$PBH_WEBUI_PORT'/p}}' $PBH_CFG)
	sed '/^server:/a\'"$PBH_PORT_STR"'' -i $PBH_CFG
fi

# 初始化 PeerBanHelper 下载器
grep -q '^client: *$' $PBH_CFG || echo client: >>$PBH_CFG
[ $(sed -n '/^client:/,/^[^ ]/{/^ \+BitCometDocker:/p}' $PBH_CFG) ] || {
	echo PeerBanHelper 未配置本机 BitComet，执行初始化 | LOG
	cat >/tmp/PBH_CLIENT_STR <<EOF
  BitCometDocker:
    type: bitcomet
    endpoint: http://127.0.0.1:$BITCOMET_WEBUI_PORT
    username: $WEBUI_USERNAME
    password: $WEBUI_PASSWORD
    http-version: HTTP_2
    increment-ban: true
    verify-ssl: false
EOF
	sed '/^client:/r/tmp/PBH_CLIENT_STR' -i $PBH_CFG
}
PBH_CLIENT_SPACE=$(sed -n '/^client:/,/^[^ ]/{/^ \+BitCometDocker:/p}' $PBH_CFG | grep -o '^ \+')
[ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/: \+'$WEBUI_USERNAME' *$/p}' $PBH_CFG)" ] || {
	echo PeerBanHelper 配置中的本机 BitComet WebUI 用户名不正确，执行更正 | LOG
	if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+username:/p}' $PBH_CFG)" ]; then
		sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s/username:.*/username: '$WEBUI_USERNAME'/}' -i $PBH_CFG
	else
		PBH_CLIENT_USERNAME_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s/type:.*/username: '$WEBUI_USERNAME'/p}}' $PBH_CFG)
		sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_USERNAME_STR"'' -i $PBH_CFG
	fi
}
[ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/: \+'$WEBUI_PASSWORD' *$/p}' $PBH_CFG)" ] || {
	echo PeerBanHelper 配置中的本机 BitComet WebUI 密码不正确，执行更正 | LOG
	if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+password:/p}' $PBH_CFG)" ]; then
		sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s/password:.*/password: '$WEBUI_PASSWORD'/}' -i $PBH_CFG
	else
		PBH_CLIENT_PASSWORD_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s/type:.*/password: '$WEBUI_PASSWORD'/p}}' $PBH_CFG)
		sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_PASSWORD_STR"'' -i $PBH_CFG
	fi
}
[ $(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/endpoint/p}' $PBH_CFG | grep -oE :$BITCOMET_WEBUI_PORT/?$) ] || {
	echo PeerBanHelper 配置中的本机 BitComet WebUI 地址不正确，执行更正 | LOG
	if [ "$(sed -n '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{/^ \+endpoint:/p}' $PBH_CFG)" ]; then
		sed '/^ \+BitCometDocker:/,/^'"$PBH_CLIENT_SPACE"'[^ ]\|^[^ ]/{s,endpoint:.*,endpoint: http://127.0.0.1:'$BITCOMET_WEBUI_PORT',}' -i $PBH_CFG
	else
		PBH_CLIENT_ENDPOINT_STR=$(sed -n '/^client:/,/^[^ ]/{/^ \+type:/{s,type:.*,endpoint: http://127.0.0.1:'$BITCOMET_WEBUI_PORT',p}}' $PBH_CFG)
		sed '/^ \+BitCometDocker:/a\'"$PBH_CLIENT_ENDPOINT_STR"'' -i $PBH_CFG
	fi
}

# 初始化 STUN
rm -f /BitComet/DockerStunPort* /BitComet/DockerStunUpnpInterface /BitComet/DockerStunUpnpConflict*
[ "$STUN" = 0 ] || {
	echo 已启用 STUN，更新 STUN 服务器列表，最多等待 15 秒 | LOG
	echo -ne "GET /stun_servers_ipv4_rst.txt HTTP/1.1\r\nHost: oniicyan.pages.dev\r\nConnection: close\r\n\r\n" | \
	timeout 15 openssl s_client -connect oniicyan.pages.dev:443 -quiet 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}' >/tmp/DockerStunServers.txt
	# wget -qT 15 https://oniicyan.pages.dev/stun_servers_ipv4_rst.txt -O /tmp/DockerStunServers.txt
	if [ -s /tmp/DockerStunServers.txt ]; then
		echo 更新 STUN 服务器列表成功 | LOG
		mv -f /tmp/DockerStunServers.txt /BitComet/DockerStunServers.txt
	else
		echo 更新 STUN 服务器列表失败，本次跳过 | LOG
		[ -f /BitComet/DockerStunServers.txt ] || cp /files/stun_servers_ipv4_rst.txt /BitComet/DockerStunServers.txt
	fi
	[ $StunMode ] || echo 未指定 STUN 穿透模式，自动设置 | LOG
	[ $StunMode ] && [[ ! "$StunMode" =~ ^(tcp|udp|nfttcp|nftudp|nftboth)$ ]] && {
		echo 错误的 STUN 穿透模式，重新设置 | LOG
		unset StunMode
	}
	[ $StunMode ] || \
	if nft list tables >/dev/null 2>&1; then
		echo 已开启 NET_ADMIN 权限，使用 TCP 改包模式 | LOG
		export StunMode=nfttcp
	else
		echo 未开启 NET_ADMIN 权限，使用 TCP 传统模式 | LOG
		export StunMode=tcp
	fi
	if [[ $StunMode =~ nft ]] && ! nft list tables >/dev/null 2>&1; then
		echo 已指定 nftables 改包模式，但未开启 NET_ADMIN 权限；自动设置为传统模式 | LOG
		[[ $StunMode =~ ^nftudp$ ]] || export StunMode=tcp
		[[ $StunMode =~ ^nftudp$ ]] && export StunMode=udp
	fi
	[ $StunMode = tcp ] && echo 当前使用 TCP 传统模式 | LOG && L4PROTO=tcp
	[ $StunMode = udp ] && echo 当前使用 UDP 传统模式 | LOG && L4PROTO=udp
	[ $StunMode = nfttcp ] && echo 当前使用 TCP 改包模式 | LOG && L4PROTO=tcp
	[ $StunMode = nftudp ] && echo 当前使用 UDP 改包模式 | LOG && L4PROTO=udp
	[ $StunMode = nftboth ] && echo 当前使用 TCP + UDP 改包模式 | LOG && L4PROTO=tcp
	[ $StunModeLite ] && [[ $StunMode =~ nft ]] && echo 已启用轻量改包模式，不支持 HTTPS Tracker 且 BitComet BT 端口必须为 5 位数 | LOG
	[ $StunModeLite ] && [[ ! $StunMode =~ nft ]] && echo StunModeLite 不适用于传统模式，已忽略 | LOG && unset StunModeLite
}

# 初始化 BitComet BT 端口
[ $BITCOMET_BT_PORT ] || [[ "$StunMode" =~ ^(tcp|udp)$ ]] || export BITCOMET_BT_PORT=$(grep ListenPort $BC_CFG | grep -oE '>.*<' | tr -d '><')
if [ $BITCOMET_BT_PORT ]; then
	if [[ $BITCOMET_BT_PORT =~ ^[0-9]+$ ]] && [ $BITCOMET_BT_PORT -le 65535 ]; then
		if [ $StunModeLite ] && [ $BITCOMET_BT_PORT -lt 10000 ]; then
			echo 轻量改包模式下要求 BitComet BT 端口为 5 位数，重新分配 | LOG
			BC_BT_PORT_FLAG=1
		else
			[ $BITCOMET_BT_PORT -ge 1024 ] || echo BitComet BT 端口指定为 1024 以下，可能无法监听 | LOG
			BC_BT_PORT_ORIG=$BITCOMET_BT_PORT
		fi
	else
		echo BitComet BT 端口指定错误，仅接受 65535 以下数字，重新分配 | LOG
		BC_BT_PORT_FLAG=1
	fi
else
	echo BitComet BT 端口未指定，自动分配 | LOG
	BC_BT_PORT_FLAG=1
fi
[ $BC_BT_PORT_FLAG ] && {
	[ $StunModeLite ] && export BITCOMET_BT_PORT=56082
	[ $StunModeLite ] || export BITCOMET_BT_PORT=6082
}
while \
	# echo | timeout 1 socat - tcp4:0.0.0.0:$BITCOMET_BT_PORT >/dev/null 2>&1 || \
	# echo | timeout 1 socat - udp4:0.0.0.0:$BITCOMET_BT_PORT >/dev/null 2>&1 || \
	awk '{print$2,$4}' /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6 | grep 0A | grep -qiE '(0{8}|0{32}):'$(printf '%04x' $BITCOMET_BT_PORT)'' && \
	echo $BITCOMET_BT_PORT | grep -qE '^'$BITCOMET_WEBUI_PORT'$|^'$PBH_WEBUI_PORT'$'
do
	export BITCOMET_BT_PORT=$(shuf -i 10000-65535 -n 1)
	BC_BT_PORT_SHUF=1
done
[ $BC_BT_PORT_ORIG ] && [ $BC_BT_PORT_SHUF ] && echo BitComet BT 端口 $BC_BT_PORT_ORIG 被占用，已重新分配 | LOG
echo BitComet BT 端口当前为 $BITCOMET_BT_PORT | LOG

# 检测 NAT 映射行为
GET_NAT() {
	echo 使用 $1/$L4PROTO 进行第 $2 次绑定请求 | LOG
	[ $StunInterface ] && \
	if [[ "$StunInterface" =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
		local StunInterface=',bind='$StunInterface''
	else
		local StunInterface=',interface='$StunInterface''
	fi
	for SERVER in $(sort -R /tmp/DockerStunServers.txt); do
		local IP=$(echo $SERVER | awk -F : '{print$1}')
		local PORT=$(echo $SERVER | awk -F : '{print$2}')
		local HEX=$(echo "000100002112a442$(head -c 12 /dev/urandom | xxd -p)" | xxd -r -p | eval timeout 2 socat - ${L4PROTO}4:$IP:$PORT,reuseport,sourceport=$1$StunInterface 2>/dev/null | xxd -p -c 64 | grep -oE '002000080001.{12}')
		if [ $HEX ]; then
			eval HEX$2=$HEX
			eval SERVER$2=$SERVER
			break
		else
			echo STUN 服务器 $SERVER 不可用，后续排除 | LOG
			sed '/^'$SERVER'$/d' -i /tmp/DockerStunServers.txt
		fi
	done
}
[ "$STUN" = 0 ] || {
	echo 检测 NAT 映射行为 | LOG
	[ $StunInterface ] && [ ! $(ls /sys/class/net | grep ^$StunInterface$) ] && {
		echo STUN 绑定端口不存在，已忽略 | LOG
		unset StunInterface
	}
	cp -f /BitComet/DockerStunServers.txt /tmp/DockerStunServers.txt
	echo 已获取 $(wc -l < /tmp/DockerStunServers.txt) 个 STUN 服务器 | LOG
	GET_NAT $BITCOMET_BT_PORT 1
	[ $HEX1 ] && \
	GET_NAT $BITCOMET_BT_PORT 2
	if [ $HEX1 ] && [ $HEX2 ]; then
		if [ ${HEX1:12:4} = ${HEX2:12:4} ]; then
			if [ $((0x${HEX1:12:4}^0x2112)) = $BITCOMET_BT_PORT ]; then
				echo 内外端口一致，当前网络具备公网 IP | LOG
				echo 自动禁用 STUN，请自行开放端口 | LOG
				export STUN=0
			else
				echo 两次端口一致，当前网络为锥形 NAT | LOG
				echo 保持启用 STUN | LOG
			fi
		else
			echo 两次端口不同，额外检测两次 | LOG
			GET_NAT $BITCOMET_BT_PORT 3
			GET_NAT $BITCOMET_BT_PORT 4
			if [[ "${HEX3:12:4}" =~ ^(${HEX1:12:4}|${HEX2:12:4}|${HEX4:12:4})$ ]] || [[ "${HEX4:12:4}" =~ ^(${HEX1:12:4}|${HEX2:12:4}|${HEX3:12:4})$ ]]; then
				echo 额外检测获得一致端口，请确认是否开启策略分流或透明代理等 | LOG
				echo 保持启用 STUN | LOG
			else
				echo 多次端口不同，当前网络为对称形 NAT | LOG
				echo 自动禁用 STUN，请优化 NAT 类型后再尝试 | LOG
				export STUN=0
			fi
		fi
		echo 检测结果如下 | LOG
		echo $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX1:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX1:12:4}^0x2112)) via $SERVER1 | LOG
		echo $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX2:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX2:12:4}^0x2112)) via $SERVER2 | LOG
		[ $HEX3 ] && \
		echo $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX3:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX3:12:4}^0x2112)) via $SERVER3 | LOG
		[ $HEX4 ] && \
		echo $(printf '%d.%d.%d.%d\n' $(printf '%x\n' $((0x${HEX4:16:8}^0x2112a442)) | sed 's/../0x& /g')):$((0x${HEX4:12:4}^0x2112)) via $SERVER4 | LOG
	else
		echo 检测 NAT 映射行为失败，本次跳过 | LOG
	fi
}

# 初始化 sslsplit
[ $StunModeLite ] || {
	STUN_ID=DockerStunCA_$(echo $HOSTNAME | sed 's/[[:punct:]]/_/g')
	mkdir -p /usr/local/share/ca-certificates/
	openssl genrsa -out $STUN_ID.key 2048
	openssl req -new -x509 -days 3650 -key $STUN_ID.key -out $STUN_ID.crt -subj "/C=CN/ST=Shanghai/L=Shanghai/O=BitCometPostBar/OU=STUN/CN=STUN_CA"
	cp -f $STUN_ID.crt /usr/local/share/ca-certificates/
	update-ca-certificates >/dev/null 2>&1
}

# 执行 NATMap 及 BitComet
if [ "$STUN" = 0 ]; then
	echo 已禁用 STUN，直接启动 BitComet | LOG
	/files/BitComet/bin/bitcometd &
else
	echo 已启用 STUN，BitComet BT 端口 $BITCOMET_BT_PORT 将作为 NATMap 的绑定端口 | LOG
	StunBindPort=$BITCOMET_BT_PORT
	while (>/dev/tcp/0.0.0.0/$BITCOMET_BT_PORT) 2>/dev/null || echo $BITCOMET_BT_PORT | grep -qE '^'$BITCOMET_WEBUI_PORT'$|^'$PBH_WEBUI_PORT'$|^'$StunBindPort'$' ; do
		export BITCOMET_BT_PORT=$(shuf -i 1024-65535 -n 1)
	done
	echo 启动 BitComet 后执行 NATMap | LOG
	/files/BitComet/bin/bitcometd &
	sleep 3
	[ $StunServer ] || export StunServer=turn.cloudflare.com
	[ $StunHttpServer ] || export StunHttpServer=qq.com
	[ $StunInterval ] || export StunInterval=25
	[ $StunInterface ] && export StunInterface='-i '$StunInterface''
	echo 本次 NATMap 执行命令
	if [ $StunMode = nftboth ]; then
		STUN_START_TCP='natmap '$StunArgs' -d -4 -s '$StunServer' -h '$StunHttpServer' -b '$StunBindPort' -k '$StunInterval' '$StunInterface' -e /files/natmap.sh'
		STUN_START_UDP='natmap '$StunArgs' -d -4 -s '$StunServer' -h '$StunHttpServer' -b '$StunBindPort' -k '$StunInterval' '$StunInterface' -e /files/natmap.sh -u'
		echo $STUN_START_TCP
		echo $STUN_START_UDP
		eval $STUN_START_TCP
		eval $STUN_START_UDP
	else
		[[ $StunMode =~ tcp ]] && \
		STUN_START='natmap '$StunArgs' -d -4 -s '$StunServer' -h '$StunHttpServer' -b '$StunBindPort' -k '$StunInterval' '$StunInterface' -e /files/natmap.sh'
		[[ $StunMode =~ udp ]] && \
		STUN_START='natmap '$StunArgs' -d -4 -s '$StunServer' -h '$StunHttpServer' -b '$StunBindPort' -k '$StunInterval' '$StunInterface' -e /files/natmap.sh -u'
		echo $STUN_START
		eval $STUN_START
	fi
fi

# 执行 PeerBanHelper
if [ "$PBH" = 0 ]; then
	echo 已禁用 PeerBanHelper | LOG
	exec sleep infinity
else
	echo 已启用 PeerBanHelper，60 秒后启动 | LOG
	sleep 60
	cd /PeerBanHelper
	java $JvmArgs -Dpbh.release=docker -Djava.awt.headless=true -Xmx512M -Xms16M -Xss512k -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+ShrinkHeapInSteps -jar /files/PeerBanHelper/PeerBanHelper.jar &
	exec sleep infinity
fi
