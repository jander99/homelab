# My Homelab Setup #

This repository will house the compose files and scripts that I use to build my Homelab along with an export of my current network map.

## Directory Structure ## 

1. ./\<container-name>/docker-compose.yml - The docker compose file used by the script to run the container. 
1. ./\<container-name>/run.sh - Shell script to load any envvars, check any dependencies, pull, and execute the container. 

### The `secrets` directory ###

It's a secret. 

## Local-Network Containers ##  
These Docker containers will run on the local network, i.e. same network as the host(s) (192.168.1.x)  
Use of the macvlan driver is required to allow Docker to assign MAC addresses on the host's interface in the Local network and therefore separate IP addresses. The amount of ports required for some of the apps will eventually cause a collision, for instance 80, 8080, 443, etc so we prefer to assign the containers requiring emulation of the Local network an IP address on the same subnet as the rest of the physical devices. 

### Pihole ###  
![Docker Stars](https://img.shields.io/docker/stars/pihole/pihole)  
  
Project  
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/pihole/pihole/v4.4)  
Latest  
![Docker Image Version (latest semver)](https://img.shields.io/docker/v/pihole/pihole?sort=semver)


Pihole is a DNS server that can be used to block advertiser domain names. Browsers, apps, and devices simple never receive routing information about the domain names in the pihole list by sending the DNS queries into a blackhole. Originally built to run on a Raspberry Pi, a docker image has been created to allow users to run it in a virtual environment. 

### Unifi ###
![Docker Stars](https://img.shields.io/docker/stars/jacobalberty/unifi)  
  
Project  
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/jacobalberty/unifi/stable)  
Latest  
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/jacobalberty/unifi?sort=semver)

The Unifi controller is an integral part of the Unifi network ecosystem, acting as the command and control center for Unifi routers, switches, and access points. 

### Træfik ###
![Docker Stars](https://img.shields.io/docker/stars/_/traefik)  
  
Project  
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/_/traefik/v2.2.1)  
Latest  
![Docker Image Version (tag latest semver)](https://img.shields.io/docker/v/_/traefik?sort=semver)  

Traefik is a CNCF member project that is working to build a cloud native edge router in Go. For this project, Traefik will act an HTTP proxy and it's IP address will be the only one open to the outside world. All Host-Network Containers will proxy through Traefik. 

## Docker-Network Containers ##  
These Docker cotnainers will run on a Docker host network 

## ENVVars ##

The following environment variables should be set for each container

IP_ADDR  
HOSTNAME  

