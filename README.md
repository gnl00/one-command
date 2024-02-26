# Docker install from one command



## Prepare

* [Download docker](https://download.docker.com/linux/static/stable/x86_64/)
* [Download docker-compose binary file](https://github.com/docker/compose/releases)



**Get docker-compose-plugin**

```shell
# 1. add docker repository https://docs.docker.com/engine/install/debian/
# 2. search docker-compose-plugin
cd /opt && apt download docker-compose-plugin
# or
yum install --downloadonly --downloaddir=/opt docker-compose-plugin

# 2. install by dpkg -i or yum localinstall
```

**Get iptables**

```shell
apt download iptables
# 
```



Then put docker-compose-plugin and iptables to ./lib dir



## Run

```shell
./install.sh -m off -y
```



## DONE
* install docker from network
* install docker from local files
* mysql deploy from dockerhub
* nginx deploy from dockerhub

## TODO
* ~~mysql deploy from local~~ Done
* ~~nginx deploy from local~~ Done
* more...

## Bugs Fix
* ~~install iptables from offline env (for docker)~~ Done
