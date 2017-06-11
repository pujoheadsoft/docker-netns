#!/bin/sh

# container の pid を取得
get_container_pid() {
    echo `docker inspect ${1} --format {{.State.Pid}}`
}

# container の name を取得
get_container_name() {
    echo `docker inspect ${1} --format {{.Name}}`
}

# container の ネットワーク名前空間(通常見えない)を ip netns コマンドで認識できるようにする
# ネットワーク名前空間を作成すると通常は /var/run/netns/ 配下に名前が追加される。
# /proc配下にcontainerのプロセスが属するnetnsを操作するFDへのリンクがあるので、/var/run/netns 配下にリンクを貼る。
# すると ip netns コマンドでcontainerの名前空間が見られるようになる。
container_netns_to_visible() {
    container_id=$1
    pid=$2
    ln -sf /proc/$pid/ns/net /var/run/netns/$container_id
}

containers_netns_to_visible() {
    container_ids=$*
    for container_id in ${container_ids}; do
	pid=`get_container_pid ${container_id}`
	container_netns_to_visible ${container_id} ${pid}
    done
}

container_netns_to_invisible() {
    container_id=$1
    rm -f /var/run/netns/$container_id
}

containers_netns_to_invisible() {
    container_ids=$*
    for container_id in ${container_ids}; do
	container_netns_to_invisible ${container_id}
    done
}

get_veth_index() {
    container_id=$1
    # container の eth0 のインデックスを取得
    index=$(ip netns exec "${container_id}" ip link show eth0 2>/dev/null | head -1 | sed 's/:.*//')
    if [ "${index}" != "" ]; then
	# ペアになるvethのindexは常にこのインデックスを+1したものになる
	echo $((index+1))
    else
	echo ${index}
    fi
}

# vethの名前を取得
get_veth_interface() {
    container_id=$1
    index=`get_veth_index ${container_id}`
    if [ "${index}" != "" ]; then
	echo `ip link show | grep "^${index}:" | sed "s/${index}: \(.*\):.*/\1/g" | sed "s/@.*//g"`
    else
	echo ${index}
    fi
}

print_veth2container() {
    container_ids=$*
    printf "%-20s %-20s %-30s\n" "VETH" "CONTAINER ID" "NAMES"
    for container_id in ${container_ids}; do
	veth_name=`get_veth_interface ${container_id}`
	if [ "${veth_name}" != "" ]; then
	    container_name=`get_container_name ${container_id}`
	    printf "%-20s %-20s %-30s\n" "${veth_name}" "${container_id}" "${container_name}"
	fi
    done
}

get_veth_ip() {
    container_id=$1
    echo `ip netns exec "${container_id}" ip addr show eth0 2>/dev/null | grep "inet " | sed 's/^ *//'`
}

print_containers_ip() {
    container_ids=$*
    printf "%-15s %-40s %s\n" "CONTAINER ID" "IP" "NAMES"
    for container_id in ${container_ids}; do
	veth_ip=`get_veth_ip ${container_id}`
	if [ "${veth_ip}" != "" ]; then
	    container_name=`get_container_name ${container_id}`
	    printf "%-15s %-40s %s\n" "${container_id}" "${veth_ip}" "${container_name}"
	fi
    done
}

usage() {
    echo "docker-netns.sh [visible | inbisible | showveth | showip]"
    echo "    visible:   docker container's network namespace to visible."
    echo "    inbisible: docker container's network namespace to invisible."
    echo "    showveth:  show docker container's veth."
    echo "    showip:    show docker container's eth0 ip address."
}

mkdir -p /var/run/netns
container_ids=$(docker ps --format {{.ID}})

case ${1} in
    visible)
	containers_netns_to_visible $container_ids
	echo "container's network namespace to visible, you can show container's nemespace by [ip netns] command."
	;;

    invisible)
	containers_netns_to_invisible $container_ids
	echo "container's network namespace to invisible"
	;;

    showveth)
	containers_netns_to_visible $container_ids
	print_veth2container $container_ids
	containers_netns_to_invisible $container_ids
	;;

    showip)
	containers_netns_to_visible $container_ids
	print_containers_ip $container_ids
	containers_netns_to_invisible $container_ids
	;;

    help|--help|-h)
	usage
	;;

    *)
	echo "[ERROR] Invalid subcommand '${1}'"
	usage
	exit 1
	;;
esac

