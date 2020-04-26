#!/bin/sh

# Use docker-compose to build the networks
export IPINTERFACE=`ip link | grep "MASTER" | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}' | awk '{$1=$1};1'`

docker-compose -f networks-compose.yml --verbose up 