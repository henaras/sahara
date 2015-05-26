#!/bin/bash
#
# Usage: bash provision_cluster.sh
#
# This script create a demo cloudera cluster.
#
# Please provide Testbed's credentials by setting the variables: OS_USERNAME,
# OS_PASSWORD, OS_AUTH_URL, OS_TENANT_NAME, OS_REGION_NAME
#
# For example:
# export OS_USERNAME=YOUR_USERNAME
# export OS_PASSWORD=YOUR_PASSWORD
# export OS_AUTH_URL=http://iam.savitestbed.ca:5000/v2.0
# export OS_TENANT_NAME=demo2
# export OS_REGION_NAME=EDGE-CT-1

export OS_AUTH_URL=http://iam.savitestbed.ca:5000/v2.0
export OS_TENANT_NAME=yorku


echo "Enter your SAVI username:"
read user_name
export OS_USERNAME=$user_name

read -s -p "Password:" pass
export OS_PASSWORD=$pass


echo -e "\nEnter the Region Name:(e.g. EDGE-TR-1, EDGE-MG-1, CORE or other edges)"
read region_name
export OS_REGION_NAME=$region_name

set -e

if [ -z "$OS_PASSWORD" ]; then
    echo "The environment variable OS_PASSWORD is not set."
    exit 1
fi

# print commands and outputs after here
set -x

if [ -z "$OS_USERNAME" ]; then
    echo "The environment variable OS_USERNAME is not set."
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


if [ -d "./tmp" ]; then
   rm -fr ./tmp
   mkdir ./tmp
else
   mkdir ./tmp
fi

# delete cluster with the samce name if exists
sahara cluster-delete --name cdh-cluster || true
sahara cluster-template-delete --name cdh5-cluster-template || true
sahara node-group-template-delete --name cloudera-master-tmpl || true
sahara node-group-template-delete --name cloudera-worker-tmpl || true
sahara node-group-template-delete --name cloudera-sec-master-tmpl || true
sahara node-group-template-delete --name cloudera-manager-tmpl || true

# master node template
cat >./tmp/ng_master_template_create.json <<EOL
{
    "name": "master-tmpl",
    "flavor_id": "2",
    "plugin_name": "cdh",
    "hadoop_version": "5",
    "node_processes": ["JOBHISTORY", "NAMENODE", "OOZIE_SERVER", "RESOURCEMANAGER"],
    "auto_security_group": false
}
EOL

sahara node-group-template-create --json ./tmp/ng_master_template_create.json
master_template_id=`sahara node-group-template-show --name cdh-master-tmpl | awk '/ id / {print $4}'`

# secondary master node template
cat >./tmp/ng_sec_master_template_create.json <<EOL
{
    "name": "sec-master-tmpl",
    "flavor_id": "2",
    "plugin_name": "cdh",
    "hadoop_version": "5",
    "node_processes": ["SECONDARYNAMENODE"],
    "auto_security_group": false
}
EOL

sahara node-group-template-create --json ./tmp/ng_sec_master_template_create.json
sec_master_template_id=`sahara node-group-template-show --name cdh-sec-master-tmpl | awk '/ id / {print $4}'`

# manager node template
cat >./tmp/ng_manager_template_create.json <<EOL
{
    "name": "manager-tmpl",
    "flavor_id": "2",
    "plugin_name": "cdh",
    "hadoop_version": "5",
    "node_processes": ["MANAGER"],
    "auto_security_group": false
}
EOL

sahara node-group-template-create --json ./tmp/ng_manager_template_create.json
manager_template_id=`sahara node-group-template-show --name cdh-manager-tmpl | awk '/ id / {print $4}'`

# worker node template
cat >./tmp/ng_worker_template_create.json <<EOL
{
    "name": "worker-tmpl",
    "flavor_id": "2",
    "plugin_name": "cdh",
    "hadoop_version": "5",
    "node_processes": ["NODEMANAGER", "DATANODE"],
    "auto_security_group": false
}
EOL

sahara node-group-template-create --json ./tmp/ng_worker_template_create.json
worker_template_id=`sahara node-group-template-show --name cdh-worker-tmpl | awk '/ id / {print $4}'`

# cluster template
cat >./tmp/cluster_template_create.json <<EOL
{
    "name": "cdh-cluster-template",
    "plugin_name": "cdh",
    "hadoop_version": "5",
    "node_groups": [
        {
            "name": "master",
            "node_group_template_id": "${master_template_id}",
            "count": 1
        },
        {
            "name": "sec-master",
            "node_group_template_id": "${sec_master_template_id}",
            "count": 1
        },
        {
            "name": "manager",
            "node_group_template_id": "${manager_template_id}",
            "count": 1
        },
        {
            "name": "workers",
            "node_group_template_id": "${worker_template_id}",
            "count": 3
        }
    ]
}

EOL
sahara cluster-template-create --json ./tmp/cluster_template_create.json
cluster_template_id=`sahara cluster-template-show --name cdh-cluster-template | awk '/ id / {print $4}'`

# provision cluster
image_id=`nova image-list | awk '/ ubuntu_sahara_cloudera_5_0_0/ {print $2}'`
keypair=`nova keypair-list | awk 'NR==4 {print $2}'`
cat >./cluster_create.json <<EOL
{
    "name": "cdh-cluster",
    "plugin_name": "cdh",
    "hadoop_version": "5",
    "cluster_template_id" : "${cluster_template_id}",
    "user_keypair_id": "${keypair}",
    "default_image_id": "${image_id}"
}
EOL
sahara cluster-create --json cluster_create.json
