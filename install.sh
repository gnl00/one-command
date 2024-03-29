#!/bin/bash

###############################################################

OS_DEV=""
PKG_MANAGER=""

###############################################################

RUNNING_MODE=""
FAST_INSTALL=false

###############################################################

readonly DOCKER_URL="https://get.docker.com"
DOCKER_INSTALLED=false
DOCKER_NOT_INSTALL=true
TRY_RERUN_DOCKER=1

readonly DOCKER_PKG=./lib/docker.tgz
readonly DOCKER_COMPSOE_DEBIAN=docker-compose-plugin_2.24.5-1~ubuntu.22.04~jammy_amd64.deb
readonly DOCKER_COMPSOE_RHEL=docker-compose-plugin-2.24.5-1.el8.x86_64.rpm

###############################################################

readonly MYSQL_CONTAINER_NAME=mysql
readonly MYSQL_TAG="5.7.44"
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD="123456" # IMPORTANT!!! Empty password before push to network

readonly MYSQL_LOAD_FILE=mysql-5.7.44.tar

readonly MYSQL_LOCAL_CNF=my.cnf
readonly MYSQL_CNF=/etc/my.cnf
readonly MYSQL_DIR=/var/lib/mysql # mysql binlog also store in /var/lib/mysql

###############################################################

readonly NGINX_CONTAINER_NAME=nginx
readonly NGINX_TAG="latest"
NGINX_PORT=80

readonly NGINX_LOAD_FILE=nginx.tar

readonly NGINX_HTML_DIR=/opt/app/client # for html
# NGINX_STATIC_DIR=/opt/app/client/static # static 目录直接放在 /opt/app/client/static
readonly NGINX_LOG_DIR=/opt/app/client/nginx-logs # for logs

readonly NGINX_CONF=nginx.conf
readonly NGINX_CUSTOM_CONF=custom.conf

readonly NGINX_CONF_PATH=/opt/app/client/nginx.conf
readonly NGINX_CUSTOM_CONF_PATH=/opt/app/client/custom.conf

NGINX_EXPORT_PORT=""

###############################################################

mysql_deploy() {
	echo "### MySQL deploying ###"

	if [[ $RUNNING_MODE = 'off' ]]; then
		echo "### Running on offline mode, loading mysql image"
		docker load -i ./docker-imgs/$MYSQL_LOAD_FILE

		local MYSQL_LOAD_RES=$?
		if [[ $MYSQL_LOAD_RES -ne 0 ]]; then
			echo "[ERROR] mysql load failed"
			exit 1
		fi
	fi

	# clean relavent docker container
	local CONTAINER_EXIST=$(docker ps -aqf "name=$MYSQL_CONTAINER_NAME")
	if [[ $CONTAINER_EXIST ]] && [[ -n $CONTAINER_EXIST ]]; then
		echo "Stop and remove stale container"
		docker stop $MYSQL_CONTAINER_NAME && docker rm $MYSQL_CONTAINER_NAME > /dev/null
	fi

	echo "### Prepare MySQL relavent files and paths"
	sudo cp ./config/$MYSQL_LOCAL_CNF /etc/
	mkdir -p $MYSQL_DIR

	echo "Input MySQL port: (default is 3306, key [enter] for default)"
	read MYSQL_IPT_PORT
	if [[ $MYSQL_IPT_PORT ]]; then
		MYSQL_PORT=$MYSQL_IPT_PORT
	else
		echo -e "Use default port: 3306\n"
	fi

	echo "Input MySQL password for root: (default is 123456, key [enter] for default)"
	read MYSQL_IPT_PWD
	if [[ $MYSQL_IPT_PWD ]]; then
		MYSQL_ROOT_PASSWORD=$MYSQL_IPT_PWD
	else
		echo -e "Use default password: 123456\n"
	fi

	# MySQL 5.7 container high memory usage: https://github.com/docker-library/mysql/issues/579
	# how to solve? add --ulimit nofile=262144:262144 when running container
	local MYSQL_DOCKER_CMD="docker run \
					--name=$MYSQL_CONTAINER_NAME -d \
					--restart always \
					-p $MYSQL_PORT:3306 \
					-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
					-v $MYSQL_CNF:$MYSQL_CNF \
					-v $MYSQL_DIR:$MYSQL_DIR \
					--ulimit nofile=262144:262144 \
					mysql:$MYSQL_TAG"

	echo "### Docker command for MySQL:"
	echo $MYSQL_DOCKER_CMD
	echo ""

	echo "### Executing Docker command..."
	local MYSQL_CONTAINER_ID=$($MYSQL_DOCKER_CMD)
	local MYSQL_IS_RUNNING=$(docker ps -qf "name=$MYSQL_CONTAINER_NAME")

	if [[ $MYSQL_IS_RUNNING ]] && [[ -n $MYSQL_IS_RUNNING ]]; then
		echo "### MySQL deployed, container id: "
		echo $MYSQL_CONTAINER_ID
	else
		echo -e "[ERROR] MySQL deploy failed"

		# Unnecessary?
		# echo "### Cleaning up"
		# MYSQL_CONTAINER_CREATED=$(docker ps -aqf "name=$MYSQL_CONTAINER_NAME")
		# if [[ $MYSQL_CONTAINER_CREATED ]] && [[ -n $MYSQL_CONTAINER_CREATED ]]; then
		# 	docker stop $MYSQL_CONTAINER_CREATED > /dev/null && docker rm $MYSQL_CONTAINER_CREATED > /dev/null
		# fi
	fi
}

nginx_deploy() {
	echo "### Nginx deploying ###"

	if [[ $RUNNING_MODE = 'off' ]]; then
		echo "### Running on offline mode, loading nginx image"
		docker load -i ./docker-imgs/$NGINX_LOAD_FILE

		local NGINX_LOAD_RES=$?
		if [[ $NGINX_LOAD_RES -ne 0 ]]; then
			echo "[ERROR] nginx image load failed"
			exit 1
		fi
	fi

	# clean relavent docker container
	local NGINX_CONTAINER_EXIST=$(docker ps -aqf "name=$NGINX_CONTAINER_NAME")
	if [[ $NGINX_CONTAINER_EXIST ]] && [[ -n $NGINX_CONTAINER_EXIST ]]; then
		echo "### Stop and remove stale container"
		docker stop $NGINX_CONTAINER_NAME && docker rm $NGINX_CONTAINER_NAME > /dev/null
	fi

	echo "### Prepare Nginx relavent files and paths"
	mkdir -p $NGINX_HTML_DIR && mkdir -p $NGINX_LOG_DIR
	cp ./config/$NGINX_CONF $NGINX_HTML_DIR && cp ./config/$NGINX_CUSTOM_CONF $NGINX_HTML_DIR

	echo "Input Nginx port: (Default is 80, key [enter] for default. Split by \",\" for multi ports)"

	read NGINX_IPT_PORT

	if [[ $NGINX_IPT_PORT ]] && [[ -n $NGINX_IPT_PORT ]]; then
		IFS=',' read -ra ports <<< "$NGINX_IPT_PORT" # Internal Field Separator，内部字段分隔符

		for port in "${ports[@]}"; do
		    NGINX_EXPORT_PORT+="-p $port:$port "
		done

	else
		echo -e "Use default port: 80\n"
		NGINX_EXPORT_PORT="-p $NGINX_PORT:80"
	fi

	local NGINX_DOCKER_CMD="docker run \
					--name=$NGINX_CONTAINER_NAME -d \
					--restart always \
					$NGINX_EXPORT_PORT \
					-v $NGINX_CONF_PATH:/etc/nginx/nginx.conf \
					-v $NGINX_CUSTOM_CONF_PATH:/etc/nginx/conf.d/$NGINX_CUSTOM_CONF
					-v $NGINX_HTML_DIR:/usr/share/nginx/html \
					-v $NGINX_LOG_DIR:/var/log/nginx
					nginx:$NGINX_TAG"

	echo "### Docker command for Nginx:"
	echo $NGINX_DOCKER_CMD
	echo ""

	echo "### Executing Docker command..."
	local NGINX_CONTAINER_ID=$($NGINX_DOCKER_CMD)

	local NGINX_IS_RUNNING=$(docker ps -qf "name=$NGINX_CONTAINER_NAME")

	if [[ $NGINX_IS_RUNNING ]] && [[ -n $NGINX_IS_RUNNING ]]; then
		echo "### Nginx deployed, container id: "
		echo $NGINX_CONTAINER_ID
	else
		echo -e "[ERROR] Nginx deploy failed"

		# Unnecessary?
		# echo "### Cleaning up"
		# NGINX_CONTAINER_CREATED=$(docker ps -aqf "name=$NGINX_CONTAINER_NAME")
		# if [[ $NGINX_CONTAINER_CREATED ]] && [[ -n $NGINX_CONTAINER_CREATED ]]; then
		# 	docker stop $NGINX_CONTAINER_CREATED > /dev/null && docker rm $NGINX_CONTAINER_CREATED > /dev/null
		# fi
	fi

}

iptables_install() {
	if [[ $PKG_MANAGER = 'dpkg' ]]; then
    	tar -xf ./lib/iptables.tar && dpkg -i ./iptables/*.deb && rm -rf ./iptables

	elif [[ $PKG_MANAGER = 'yum' ]]; then
    	tar -xf ./lib/iptables-rhel.tar && yum localinstall -y ./iptables/*.rpm && rm -rf ./iptables
	fi
	

	local IPTABLES_EXIST=$(command -v iptables)
	if [[ -z $IPTABLES_EXIST ]]; then
		echo "[ERROR] iptables instll failed"
		exit 1
	fi
}

docker_start() {
	# Prepare Docker environment
	local IPTABLES_EXIST=$(command -v iptables)

	if [[ -z $IPTABLES_EXIST ]]; then
		echo "[WARNING] command iptables not found, installing"
		iptables_install
	fi

	systemctl start docker >/dev/null 2>&1

	local DOCKER_START_RES=$?

	if [[ $DOCKER_START_RES -ne 0 ]]; then
		echo "[ERROR] failed to start Docker"
		exit 1
	fi
}

docker_compose_install() {
	if [[ $PKG_MANAGER = 'dpkg' ]]; then
		dpkg -i ./lib/$DOCKER_COMPSOE_DEBIAN

	elif [[ $PKG_MANAGER = 'yum' ]]; then
    	yum localinstall -y ./lib/$DOCKER_COMPSOE_RHEL
	fi
}

docker_install_online() {
	echo "### Installing Docker ###"
	curl -fsSL $DOCKER_URL -o get-docker.sh
	sh get-docker.sh

	local DOCKER_INSTALL_RESULT=$(docker --version)

	if [[ $DOCKER_INSTALL_RESULT ]]; then
		DOCKER_NOT_INSTALL=false
		echo "### Docker installed"
	else
		echo -e "[ERROR] Docker install failed. Please look throw output logs and fix, run again then."
		exit 1
	fi
}

docker_install_offline() {
	echo "### Extracting Docker package"
	tar -xf $DOCKER_PKG && cp ./docker/* /usr/bin && rm -rf ./docker

	echo "### Adding Docker startup configuration"
	cp ./config/docker.service /etc/systemd/system
	chmod +x /etc/systemd/system/docker.service

	local DOCKER_INSTALL_RESULT=$(command -v docker)
	if [[ $DOCKER_INSTALL_RESULT ]]; then
		DOCKER_NOT_INSTALL=false
		echo "### Docker installed"
	else
		echo -e "[ERROR] Docker install failed. Please look throw output logs and fix, run again then."
		exit 1
	fi

	echo "### Adding docker-compose"

	docker_compose_install

	docker compose >/dev/null 2>&1
	local DOCKER_COMPOSE_RES=$?

	if [[ $DOCKER_COMPOSE_RES ]] && [[ $DOCKER_COMPOSE_RES -eq 0 ]]; then
		echo "### Docker compose installed"
	else
		echo -e "[WARNING] Docker compsoe install failed\n"
	fi

	echo "### Starting Docker"
	systemctl daemon-reload
	systemctl enable docker.service

	docker_start
}

docker_install() {
	if [[ $RUNNING_MODE = 'on' ]]; then

		echo "### Install Docker from network"
		docker_install_online

	elif [[ $RUNNING_MODE = 'off' ]]; then

		echo "### Install Docker from local files"
		docker_install_offline

	fi
}

package_manager_check() {
	# Which distributed of Linux is this?
	if which dpkg >/dev/null 2>&1; then
    	echo "### Debian-like OS"
    	PKG_MANAGER="dpkg"

	elif which yum >/dev/null 2>&1; then
	    echo "### CentOS-like OS"
    	PKG_MANAGER="yum"

	fi
}

docker_check() {
	echo "### Checking Docker"
	local DOCKER_INSTALL_RESULT=$(command -v docker)

	if [[ $DOCKER_INSTALL_RESULT ]]; then
		DOCKER_NOT_INSTALL=false
		echo "### Docker installed"
	else
		echo -e "[WARNING] Docker is not install\n"
	fi
}

warning() {
	if ! "$FAST_INSTALL"; then
		echo -e "### Before run this script, \
				\n### Please make sure you already update: \
				\n## [my.cnf] for MySQL, \
				\n## [nginx.conf] and [custom.conf] for Nginx, \
				\nPlease type in: y/no"

		read operation
		if [[ -z "$operation" ]] || [[ -n "$operation" ]] && [[ "$operation" != "y" ]]; then
		    echo "Exiting..."
		    exit 1
	    fi
	else
		echo "### Fast install"
    fi
}

helps() {
    echo "Usage: $(basename $0) [-m] [-y] [-h]"
    echo "Options:"
    echo "  -y      Optional, running in fast installation mode"
    echo "  -m      Running in online mode or offline mode, can be [on] or [off]"
}

start() {
	local DOCKER_IS_RUNNING=$(systemctl status docker | grep "running")

	if [[ $DOCKER_IS_RUNNING ]] && [[ -n $DOCKER_IS_RUNNING ]]; then
		echo -e "\n***** Docker is running *****\n"

		echo "### Which image do you want to deploy?"
		echo "### MySQL[1] Nginx[2] Exit[any key]"

		read option

		if [[ $option -eq 1 ]]; then
			mysql_deploy
		elif [[ $option -eq 2 ]]; then
			nginx_deploy
		else
			echo "Exiting..."
			exit 1
		fi

	elif [[ $TRY_RERUN_DOCKER -gt 0 ]]; then

		echo "### Try to start Docker: $TRY_RERUN_DOCKER"
		TRY_RERUN_DOCKER=`expr $TRY_RERUN_DOCKER - 1`

		docker_start

		start
	else
		echo -e "[ERROR] Docker is not running"
		exit 1
	fi
}

main() {

	echo "##### IMPORTANT!!! Please run this script with root and install [curl] before running."
	echo "##### IMPORTANT!!! Make sure [systemctl] command exist."

	warning

	package_manager_check

	docker_check

	if $DOCKER_NOT_INSTALL; then
		docker_install
	fi

	local SYS_CTL_EXIST=$(command -v systemctl)
	if [[ -z $SYS_CTL_EXIST ]]; then
		echo "[ERROR] command [systemctl] not found"
		exit 1
	fi

	start
}

###############################################################

while getopts ":m:yh" opt_name; do
    case "$opt_name" in
        'm')
            RUNNING_MODE="$OPTARG" # get option value from "$OPTARG"
            ;;
        'y')
            FAST_INSTALL=true
            ;;
        'h')
            helps
            exit 0
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
        ?)
            echo "Unknown argument(s)."
            exit 2
            ;;
    esac
done

shift $((OPTIND-1)) # get next option

# Check if this is option -m
if [ -z "$RUNNING_MODE" ]; then
	echo -e "[ERROR] Option -m is required."
	helps
	exit 1
fi

echo "***** Running mode: $RUNNING_MODE"
echo "***** Fast install: $FAST_INSTALL"
echo ""

###############################################################

main
