#!/bin/sh

# Use docker-compose to build the networks
export IPINTERFACE=`ip link | grep "MASTER" | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | awk '{$1=$1};1'`

docker network create -d macvlan -o parent=${IPINTERFACE} --subnet 192.168.1.0/24 --gateway 192.168.1.1 --ip-range 192.168.1.0/28 homelab_physical_network

