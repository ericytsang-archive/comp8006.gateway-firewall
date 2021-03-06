# run on hosts on LAN
# before running script, make sure that:
# * appropriate NICs are enabled / disabled (NETWORK_INTERFACE is enabled, the rest are disabled)
# * appropriate DNS servers have been added to the /etc/resolv.conf (syntax: nameserver x.x.x.x)

### configuration ###

# network interface to LAN
NETWORK_INTERFACE="enp3s2"

# host's address on LAN
HOST_ADDRESS="10.210.0.1"

# LAN subnet address
SUBNET_ADDRESS="10.210.0.0/24"

# WAN gateway address
GATEWAY_ADDRESS="10.210.0.2"

# DNS server addresses
NAME_SERVERS="8.8.8.8"

### code - do not touch! ###

# configure DNS servers
echo "nameserver $NAME_SERVERS" > /etc/resolv.conf

# configure network properties
ip addr replace $HOST_ADDRESS dev $NETWORK_INTERFACE valid_lft forever preferred_lft forever
ip route replace $SUBNET_ADDRESS dev $NETWORK_INTERFACE proto static
ip route replace default via $GATEWAY_ADDRESS dev $NETWORK_INTERFACE proto static
