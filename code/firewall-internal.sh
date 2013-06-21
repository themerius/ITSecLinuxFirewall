#!/bin/sh
### BEGIN INIT INFO
# Provides:          internal firewall
# Required-Start:    $local_fs $remote_fs $syslog $network
# Required-Stop:     $local_fs $remote_fs $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Internal firewall
# Description:       Internal firewall (sh, mb)
### END INIT INFO

SRV_IP=192.168.40.1
FW1_IP=192.168.40.250
DMZ_IP=192.168.40.240
DMZ_DEV="eth1"
LAN_IP=192.168.30.240
LAN_DEV="eth0"
EXT_NET=10.1.0.0/24

# vpn config (dummy)
TUN_DEV=127.0.0.1
TAP_DEV=127.0.0.1

forwardToSrv()
{
    PORT=$1
    TYPE=$2
    iptables -A FORWARD -i $LAN_DEV -o $DMZ_DEV -d $SRV_IP -p $TYPE --dport $PORT -m conntrack --ctstate NEW -j ACCEPT
}

case "$1" in
    start)
        # clear
        iptables -F
        iptables -t nat -F
        iptables -t mangle -F
        iptables -x

        # defaults
        iptables -P INPUT   DROP
        iptables -P OUTPUT  DROP
        iptables -P FORWARD DROP

        # enable Forwarding
        echo "1" > /proc/sys/net/ipv4/ip_forward

        # fw1 as gateway to extranet
        route add -net $EXT_NET gw $FW1_IP

        # loopback
        iptables -A INPUT  -i lo -j ACCEPT
        iptables -A OUTPUT -o lo -j ACCEPT

        # stateful rules (after that, only need to allow NEW connections)
        iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A OUTPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        # drop invalid state packets
        iptables -A INPUT   -m conntrack --ctstate INVALID -j DROP
        iptables -A OUTPUT  -m conntrack --ctstate INVALID -j DROP
        iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP

        # access from lan to extranet
        iptables -A FORWARD -i $LAN_DEV -o DMZ_DEV -d $EXT_NET -m conntrack --ctstate NEW -j ACCEPT

        # enable ping to this firewall server
        iptables -A INPUT -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

        # enable ping to fw1 and srv1
        iptables -A FORWARD -i $LAN_DEV -o $DMZ_DEV -d $FW1_IP -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -i $LAN_DEV -o $DMZ_DEV -d $SRV_IP -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

        # access from lan to server
        forwardToSrv  80 tcp  # http
        forwardToSrv 443 tcp  # https
        forwardToSrv  25 tcp  # smtp
        forwardToSrv  53 tcp  # dns
        forwardToSrv  53 udp  # dns

        # vpn
        iptables -A INPUT -i $DMZ_DEV -p udp --dport 1194 -m conntrack --ctstate NEW -j ACCEPT
        iptables -A INPUT -i $DMZ_DEV -p udp --dport 1195 -m conntrack --ctstate NEW -j ACCEPT

        # vpn forwarding
        iptables -A FORWARD -i $TUN_DEV -o $LAN_DEV -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -i $LAN_DEV -o $TUN_DEV -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -i $TAP_DEV -o $LAN_DEV -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -i $LAN_DEV -o $TAP_DEV -m conntrack --ctstate NEW -j ACCEPT

        # protocol all other requests
        iptables -A FORWARD -i $LAN_DEV -j LOG --log-prefix "from lan - forbidden: "
        iptables -A FORWARD -i $LAN_DEV -j DROP

        # protocol requests from DMZ
        iptables -A FORWARD -i $DMZ_DEV -j LOG --log-prefix "from dmz - forbidden: "
        iptables -A FORWARD -i $DMZ_DEV -j DROP

        echo "Firewall started."
        ;;

    stop)
        iptables -F
        iptables -P INPUT  ACCEPT
        iptables -P OUTPUT ACCEPT

        route del -net $EXT_NET

        echo "Firewall disabled."
        ;;

    restart)
        $0 stop
        sleep 1
        $0 start
        ;;

    *)
        echo "Usage $0 {start|stop|restart}"
        ;;

esac