#!/usr/bin/env bash
#
# Usage: sh install_sahara.sh
#
# This script install Sahara. To ensure this script to work properly, user
# need to provide credentials of Testbed with admin privilege.
#
# Please provide Testbed's credentials by setting the variables: OS_USERNAME,
# OS_PASSWORD, OS_AUTH_URL, OS_TENANT_NAME, OS_REGION_NAME
#
# For example:
# export OS_USERNAME=sahara
# export OS_PASSWORD=saharasecret
# export OS_AUTH_URL=http://iam.savitestbed.ca:5000/v2.0
# export OS_TENANT_NAME=service
# export OS_REGION_NAME=CORE

set -xe

function screen_it {
    SCREEN_NAME=stack
    SCREEN_HARDSTATUS='%{= .} %-Lw%{= .}%> %n%f %t*%{= .}%+Lw%< %-=%{g}(%{d}%H/%l%{g})'

    # Create a session if there is none
    if type -p screen >/dev/null && screen -ls | egrep -q "[0-9].$SCREEN_NAME"; then
        echo "A screen session have already been created."
    else
        # Create a new named screen to run processes in
        screen -d -m -S $SCREEN_NAME -t shell -s /bin/bash
        sleep 1
        # Set a reasonable statusbar
        screen -r $SCREEN_NAME -X hardstatus alwayslastline "$SCREEN_HARDSTATUS"
fi

    screen -S $SCREEN_NAME -X screen -t $1
    # sleep to allow bash to be ready to be send the command - we are
    # creating a new window in screen and then sends characters, so if
    # bash isn't running by the time we send the command, nothing happens
    sleep 1.5

    SCREEN_LOGDIR=/opt/stack/logs
    TIMESTAMP_FORMAT="%F-%H%M%S"
    CURRENT_LOG_TIME=$(date "+$TIMESTAMP_FORMAT")
    NL=`echo -ne '\015'`

    sudo mkdir -p ${SCREEN_LOGDIR}
    sudo chown -R ${USER} ${SCREEN_LOGDIR}
    screen -S $SCREEN_NAME -p $1 -X logfile ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log
    screen -S $SCREEN_NAME -p $1 -X log on
    ln -sf ${SCREEN_LOGDIR}/screen-${1}.${CURRENT_LOG_TIME}.log ${SCREEN_LOGDIR}/screen-${1}.log

    screen -S $SCREEN_NAME -p $1 -X stuff "$2$NL"
}

if [ -z "$OS_USERNAME" ]; then
    echo "The environment variable OS_USERNAME is not set."
    exit 1
fi

if [ -z "$OS_PASSWORD" ]; then
    echo "The environment variable OS_PASSWORD is not set."
    exit 1
fi

if [ -z "$OS_AUTH_URL" ]; then
    echo "The environment variable OS_AUTH_URL is not set."
    exit 1
fi

if [ -z "$OS_TENANT_NAME" ]; then
    echo "The environment variable OS_TENANT_NAME is not set."
    exit 1
fi

if [ -z "$OS_REGION_NAME" ]; then
    echo "The environment variable OS_REGION_NAME is not set."
    exit 1
fi

auth_host_with_port=`echo "${OS_AUTH_URL}" | cut -d'/' -f3`

auth_host=`echo "${auth_host_with_port}" | cut -d':' -f1`
auth_port=`echo "${auth_host_with_port}" | cut -d':' -f2`

if [ -f /etc/nova/nova.conf ]; then
    db_root_password=`cat /etc/nova/nova.conf | awk -F '[:@]' '/connection/{print $3}'`
fi

# username and password for mysql in sahara.
db_user=sahara
db_password=saharapass

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python-setuptools \
     python-virtualenv python-dev git-core mysql-server libmysqlclient-dev python-pip

# config MySQL
if [ -n "${db_root_password}" ]; then
    mysql -uroot -p${db_root_password} -e "DROP DATABASE IF EXISTS sahara;"
    mysql -uroot -p${db_root_password} -e "CREATE DATABASE sahara;"
    mysql -uroot -p${db_root_password} -e "GRANT ALL PRIVILEGES ON sahara.* TO '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';"
else
    mysql -uroot -e "DROP DATABASE IF EXISTS sahara;"
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS sahara;"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON sahara.* TO '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';"
fi
sudo sed -i 's/max_allowed_packet.*/max_allowed_packet = 256M/g' /etc/mysql/my.cnf
sudo service mysql restart

# remove the previous installation footprints -- Hamzeh
Dir=/etc/sahara
if [ -d "$Dir" ]; then
    printf '%s\n' "Removing previous installation config directory ($Dir)"
    sudo rm -rf "$Dir"
fi

if [ -f "/bin/sahara" ]; then
    printf '%s\n' "Removing previous installation execute file (/bin/sahara)"
    sudo rm -f "/bin/sahara"
fi

Dir=/home/ubuntu/sahara/sahara-venv
if [ -d "$Dir" ]; then
    printf '%s\n' "Removing previous installation directory ($Dir)"
    sudo rm -fr "$Dir"
fi


# install Sahara
virtualenv sahara-venv
sahara-venv/bin/pip install git+https://github.com/henaras/sahara.git@stable/juno
sahara-venv/bin/pip install mysql-python
sudo mkdir /etc/sahara

echo "
[DEFAULT]
# List of plugins to be loaded. Sahara preserves the order of
# the list when returning it. (list value)
plugins=vanilla,hdp,spark,cdh
os_region_name=${OS_REGION_NAME}

debug=true
verbose=true
use_identity_api_v3=false
use_floating_ips=false

# Use Neutron or Nova Network (boolean value)
use_neutron=false

# Use network namespaces for communication (only valid to use in conjunction
# with use_neutron=True)
#use_namespaces=false

logging_exception_prefix = %(color)s%(asctime)s.%(msecs)03d TRACE %(name)s ^[[01;35m%(instance)s^[[00m
logging_debug_format_suffix = ^[[00;33mfrom (pid=%(process)d) %(funcName)s %(pathname)s:%(lineno)d^[[00m
logging_default_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [^[[00;36m-%(color)s] ^[[01;35m%(instance)s%(color)s%(message)s^[[00m
logging_context_format_string = %(asctime)s.%(msecs)03d %(color)s%(levelname)s %(name)s [^[[01;36m%(request_id)s ^[[00;36m%(user_name)s %(project_name)s%(color)s] ^[[01;35m%(instance)s%(color)s%(message)s^[[00m

[database]
connection=mysql://sahara:saharapass@localhost/sahara

[keystone_authtoken]
# Complete public Identity API endpoint (string value)
# auth_uri=${OS_AUTH_URL} # this is fine but I use the follwoing instead:
auth_uri=http://${auth_host}:5000/v2.0

# Complete admin Identity API endpoint. This should specify
# the unversioned root endpoint eg. https://localhost:35357/
# (string value)
identity_uri=http://${auth_host}:35357/

# Keystone account username (string value)
admin_user=${OS_USERNAME}

# Keystone account password (string value)
admin_password=${OS_PASSWORD}

# Keystone service account tenant name to validate user tokens
# (string value)
admin_tenant_name=${OS_TENANT_NAME}
" | sudo tee /etc/sahara/sahara.conf >/dev/null

# install Sahara client
# sahara-venv/bin/pip install git+https://github.com/hongbin/python-saharaclient.git
# new version of saharaclient
sahara-venv/bin/pip install git+https://github.com/henaras/python-saharaclient
sudo ln -s $(readlink -m ./sahara-venv/bin/sahara) /bin/sahara || true

# Installing the cloudera manager for Cloudera plugin
sudo pip install cm-api
cp -fr /usr/local/lib/python2.7/dist-packages/cm_* /home/ubuntu/sahara/sahara-venv/lib/python2.7/site-packages/

# Starting the Sahara server
sahara-venv/bin/sahara-db-manage --config-file /etc/sahara/sahara.conf upgrade head
screen_it sahara "$(readlink -m ./sahara-venv/bin/sahara-all) --config-file /etc/sahara/sahara.conf"

# register Hadoop image
#image_id=`sahara-venv/bin/nova image-list | awk '/ sahara-icehouse-vanilla-2.3.0-ubuntu-13.10 / {print $2}'`
#sahara image-register --id ${image_id} --username ubuntu
#sahara image-add-tag --id ${image_id} --tag vanilla
#sahara image-add-tag --id ${image_id} --tag 2.3.0
#sahara image-add-tag --id ${image_id} --tag ubuntu

# register Spark 1.0.0 image, we already did this.
#image_id=`sahara-venv/bin/nova image-list | awk '/ sahara-juno-spark-1.0.0-ubuntu-14.04 / {print $2}'`
#sahara image-register --id ${image_id} --username ubuntu
#sahara image-add-tag --id ${image_id} --tag spark
#sahara image-add-tag --id ${image_id} --tag 1.0.0
#sahara image-add-tag --id ${image_id} --tag ubuntu
