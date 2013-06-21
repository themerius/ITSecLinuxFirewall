#!/bin/sh
### BEGIN INIT INFO
# Provides:          external firewall
# Required-Start:    $local_fs $remote_fs $syslog $network
# Required-Stop:     $local_fs $remote_fs $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: External firewall
# Description:       External firewall (sh, mb)
### END INIT INFO

SRV_IP=192.168.40.1
FW2_IP=192.168.40.240
DMZ_IP=192.168.40.250
DMZ_DEV="eth0"
EXT_IP=10.1.0.131
EXT_DNS=10.1.0.1
FIRMA_B=10.1.0.132
EXT_DEV="eth1"
EXT_NET=10.1.0.0/24
LAN_NET=192.168.30.0/24

forwardToSrv()
{
    PORT=$1
    iptables -t nat -A PREROUTING -i $EXT_DEV -p tcp --dport $PORT -j DNAT --to $SRV_IP
    iptables -A FORWARD -i $EXT_DEV -o $DMZ_DEV -d $SRV_IP -p tcp --dport $PORT -m conntrack --ctstate NEW -j ACCEPT
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

        # fw2 as gateway to lan
        route add -net $LAN_NET gw $FW2_IP

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

        # enable ping to this firewall server
        iptables -A INPUT -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT

        # port Forwarding from extranet
        forwardToSrv  25  # smtp
        forwardToSrv  80  # http
        forwardToSrv 443  # https

        # masquerading for packets to extranet
        iptables -t nat -A POSTROUTING -o $EXT_DEV -s $SRV_IP  -j MASQUERADE
        iptables -t nat -A POSTROUTING -o $EXT_DEV -s $LAN_NET -j MASQUERADE

        # allow forwarding from lan to extranet
        iptables -A FORWARD -i $DMZ_DEV -o $EXT_DEV -s $LAN_NET -d $EXT_NET -m conntrack --ctstate NEW -j ACCEPT

        # allow dns from srv to extranet
        iptables -A FORWARD -i $DMZ_DEV -o $EXT_DEV -s $SRV_IP -d $EXT_DNS -p tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
        iptables -A FORWARD -i $DMZ_DEV -o $EXT_DEV -s $SRV_IP -d $EXT_DNS -p udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT

        # vpn: client to lan
        iptables -t nat -A PREROUTING -i $EXT_DEV -p udp --dport 1195 -j DNAT --to $FW2_IP
        iptables -A FORWARD -i $EXT_DEV -o $DMZ_DEV -d $FW2_IP -p udp --dport 1195 -j ACCEPT

        # vpn: lan to lan
        iptables -t nat -A PREROUTING -i $EXT_DEV -s $FIRMA_B -p udp --dport 1194 -j DNAT --to $FW2_IP
        iptables -A FORWARD -i $EXT_DEV -o $DMZ_DEV -d $FW2_IP -p udp --dport 1194 -j ACCEPT

        # protocol all other requests from extranet
        iptables -A FORWARD -i $EXT_DEV -j LOG --log-prefix "from extranet - forbidden: "
        iptables -A FORWARD -i $EXT_DEV -j DROP

        # protocol all other requests from dmz
        iptables -A FORWARD -i $DMZ_DEV -j LOG --log-prefix "from dmz - forbidden: "
        iptables -A FORWARD -i $DMZ_DEV -j DROP

        echo "Firewall started."
        ;;

    stop)
        iptables -F
        iptables -P INPUT  ACCEPT
        iptables -P OUTPUT ACCEPT

        route del -net $LAN_NET

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