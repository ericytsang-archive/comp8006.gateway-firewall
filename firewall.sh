# !/bin/sh

### configuration ###

# general
IPT="iptables"
PS4='$LINENO '

# network interfaces
WAN_NIC="enp0s3"
LAN_NIC="enp0s8"

# addresses
HOST_ADDR="10.64.205.162"
SUBNET_ADDR="192.168.56.0/24"
DHCP_SERVERS="0.0.0.0/0"
DNS_SERVERS="8.8.8.8"

# allowed ICMP packet types
INBOUND_ICMP_TYPES="0"
OUTBOUND_ICMP_TYPES="8"

# TCP servers on LAN accessible from WAN
# syntax: [public port 1],[private address 1],[private port 1] [public port 2],[private address 2],[private port 2]
# example: 80,192.168.1.1,8080 22,192.168.1.5,22
LAN_TCP_SVRS="21,192.168.56.101,21 20,192.168.56.101,20 22,192.168.56.101,22 80,192.168.56.101,80"

# TCP servers on WAN accessible from LAN
WAN_TCP_SVRS="22 80 443"

# UDP servers on LAN accessible from WAN
# syntax: [public port 1],[private address 1],[private port 1] [public port 2],[private address 2],[private port 2]
# example: 80,192.168.1.1,8080 22,192.168.1.5,22
LAN_UDP_SVRS="22,192.168.56.101,22"

# UDP servers on WAN accessible from LAN
WAN_UDP_SVRS=""

# TCP traffic to minimize delay for
TCP_MINIMIZE_DELAY="22 21"

# TCP traffic to maximize throughput for
TCP_MAXIMIZE_THROUGHPUT="20"

# UDP traffic to minimize delay for
UDP_MINIMIZE_DELAY=""

# UDP traffic to maximize throughput for
UDP_MAXIMIZE_THROUGHPUT="22"

# addresses
WAN_ADDR="0.0.0.0/0"
BROADCAST_SRC_ADDR="0.0.0.0"
BROADCAST_DEST_ADDR="255.255.255.255"

# ports
UNPRIV_PORTS="1024:65535"
PRIV_PORTS="0:1023"

### implementation - do not touch! ###

# reset firewall
$IPT -F
$IPT -t nat -F
$IPT -t mangle -F
$IPT -X
$IPT -t nat -X
$IPT -t mangle -X
$IPT -P INPUT ACCEPT
$IPT -P OUTPUT ACCEPT
$IPT -P FORWARD ACCEPT

if [ "$1" = "stop" ]
then
	echo "Firewall cleared"
	exit 0
fi

# set default chain policies
$IPT -P INPUT DROP
$IPT -P OUTPUT DROP
$IPT -P FORWARD DROP

# enable forwarding and masquerading
# linuxpoison.blogspot.ca/2009/02/how-to-configure-linux-as-internet.html
$IPT -t nat -A POSTROUTING -o $WAN_NIC -j MASQUERADE

# create user chains
USER_CHAINS="DHCP DNS ICMP TCP_SVR TCP_CLNT UDP_CLNT UDP_SVR"
for CHAIN in $USER_CHAINS
do
	$IPT -N $CHAIN
	$IPT -A $CHAIN -j ACCEPT
done

# enable DHCP traffic to DHCP servers
for SVR in $DHCP_SERVERS
do
	$IPT -A OUTPUT -o $WAN_NIC -p udp \
				-s $BROADCAST_SRC_ADDR --sport 67:68 \
				-d $BROADCAST_DEST_ADDR --dport 67:68 \
				-j DHCP
	$IPT -A INPUT -i $WAN_NIC -p udp \
				-s $SVR --sport 67 \
				-d $SUBNET_ADDR --dport 68 \
				-j DHCP
	$IPT -A OUTPUT -o $WAN_NIC -p udp \
				-d $SVR --dport 67 \
				-s $HOST_ADDR --sport 68 \
				-j DHCP
	$IPT -A INPUT -i $WAN_NIC -p udp \
				-s $SVR --sport 67 \
				-d $HOST_ADDR --dport 68 \
				-j DHCP
done

# enable DNS traffic to DNS servers
for SVR_ADDR in $DNS_SERVERS
do
	$IPT -A FORWARD -p udp \
				-i $LAN_NIC -s $SUBNET_ADDR --sport $UNPRIV_PORTS \
				-o $WAN_NIC -d $SVR_ADDR --dport 53 \
				-j DNS
	$IPT -A FORWARD -p udp \
				-i $WAN_NIC -s $SVR_ADDR --sport 53 \
				-o $LAN_NIC -d $SUBNET_ADDR --dport $UNPRIV_PORTS \
				-j DNS
done

# enable inbound ICMP traffic based on type
for ICMP_TYPE in $INBOUND_ICMP_TYPES
do
	$IPT -A FORWARD -p icmp --icmp-type $ICMP_TYPE \
				-i $WAN_NIC -s $WAN_ADDR \
				-o $LAN_NIC -d $SUBNET_ADDR \
				-j ICMP
done

# enable outbound ICMP traffic based on type
for ICMP_TYPE in $OUTBOUND_ICMP_TYPES
do
	$IPT -A FORWARD -p icmp --icmp-type $ICMP_TYPE \
				-i $LAN_NIC -s $SUBNET_ADDR \
				-o $WAN_NIC -d $WAN_ADDR \
				-j ICMP
done

# port forward to enable access to LAN TCP servers from WAN
for SVR in $LAN_TCP_SVRS
do
	# parse parameters into public port, private address and private port
	IFS=","
	set $SVR
	IFS=" "
	DST_PORT=$1
	SVR_ADDR=$2
	SVR_PORT=$3

	# make firewall rules
	$IPT -A PREROUTING -t nat -i $WAN_NIC -p tcp \
				! -s $SUBNET_ADDR  --sport $UNPRIV_PORTS \
				-d $HOST_ADDR --dport $DST_PORT \
				-m state --state NEW,ESTABLISHED \
				-j DNAT --to $SVR_ADDR:$SVR_PORT
	$IPT -A FORWARD -p tcp \
				-i $WAN_NIC -s $WAN_ADDR --sport $UNPRIV_PORTS \
				-o $LAN_NIC -d $SVR_ADDR --dport $SVR_PORT \
				-m state --state NEW,ESTABLISHED -j TCP_SVR
	$IPT -A FORWARD -p tcp \
				-i $LAN_NIC -s $SVR_ADDR --sport $SVR_PORT \
				-o $WAN_NIC -d $WAN_ADDR --dport $UNPRIV_PORTS \
				-m state --state ESTABLISHED -j TCP_SVR
done

# enable outbound TCP traffic to remote TCP servers
for SVR_PORT in $WAN_TCP_SVRS
do
	$IPT -A FORWARD -p tcp \
				-i $WAN_NIC -s $WAN_ADDR --sport $SVR_PORT \
				-o $LAN_NIC -d $SUBNET_ADDR --dport $UNPRIV_PORTS \
				-m state --state ESTABLISHED -j TCP_CLNT
	$IPT -A FORWARD -p tcp \
				-i $LAN_NIC -s $SUBNET_ADDR --sport $UNPRIV_PORTS \
				-o $WAN_NIC -d $WAN_ADDR --dport $SVR_PORT \
				-m state --state NEW,ESTABLISHED -j TCP_CLNT
done

# port forward to enable access to LAN UDP servers from WAN - TODO test
for SVR in $LAN_UDP_SVRS
do
	# parse parameters into public port, private address and private port
	IFS=","
	set $SVR
	IFS=" "
	DST_PORT=$1
	SVR_ADDR=$2
	SVR_PORT=$3

	# make firewall rules
	$IPT -A PREROUTING -t nat -i $WAN_NIC -p udp \
				! -s $SUBNET_ADDR --sport $UNPRIV_PORTS \
				-d $HOST_ADDR --dport $DST_PORT \
				-j DNAT --to $SVR_ADDR:$SVR_PORT
	$IPT -A FORWARD -p udp \
				-i $WAN_NIC -s $WAN_ADDR --sport $UNPRIV_PORTS \
				-o $LAN_NIC -d $SVR_ADDR --dport $SVR_PORT \
				-j UDP_SVR
	$IPT -A FORWARD -p udp \
				-i $LAN_NIC -s $SVR_ADDR --sport $SVR_PORT \
				-o $WAN_NIC -d $WAN_ADDR --dport $UNPRIV_PORTS \
				-j UDP_SVR
done

# enable outbound UDP traffic to remote UDP servers
for SVR_PORT in $WAN_UDP_SVRS
do
	$IPT -A FORWARD -p udp \
				-i $WAN_NIC -s $WAN_ADDR --sport $SVR_PORT \
				-o $LAN_NIC -d $SUBNET_ADDR --dport $UNPRIV_PORTS \
				-j UDP_CLNT
	$IPT -A FORWARD -p udp \
				-i $LAN_NIC -s $SUBNET_ADDR --sport $UNPRIV_PORTS \
				-o $WAN_NIC -d $WAN_ADDR --dport $SVR_PORT \
				-j UDP_CLNT
done

# minimize delay for TCP traffic
for PORT in $TCP_MINIMIZE_DELAY
do
	$IPT -A FORWARD -t mangle -p tcp --sport $PORT \
				-j TOS --set-tos Minimize-Delay
	$IPT -A FORWARD -t mangle -p tcp --dport $PORT \
				-j TOS --set-tos Minimize-Delay
done

# maximize throughput for TCP traffic
for PORT in $TCP_MAXIMIZE_THROUGHPUT
do
	$IPT -A FORWARD -t mangle -p tcp --sport $PORT \
				-j TOS --set-tos Maximize-Throughput
	$IPT -A FORWARD -t mangle -p tcp --dport $PORT \
				-j TOS --set-tos Maximize-Throughput
done

# UDP traffic to minimize delay for
for PORT in $UDP_MINIMIZE_DELAY
do
	$IPT -A FORWARD -t mangle -p udp --sport $PORT \
				-j TOS --set-tos Minimize-Delay
	$IPT -A FORWARD -t mangle -p udp --dport $PORT \
				-j TOS --set-tos Minimize-Delay
done

# UDP traffic to maximize throughput for
for PORT in $UDP_MAXIMIZE_THROUGHPUT
do
	$IPT -A FORWARD -t mangle -p udp --sport $PORT \
				-j TOS --set-tos Maximize-Throughput
	$IPT -A FORWARD -t mangle -p udp --dport $PORT \
				-j TOS --set-tos Maximize-Throughput
done

# questions:
# drop all packets destined for the firewall from the outside??? including established TCP connections? how about UDP packets?
