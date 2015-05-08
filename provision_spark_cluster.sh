#!/bin/bash
#
# Usage: bash provision_cluster.sh
#
# This script create a demo Spark cluster.
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
sahara cluster-delete --name spark-cluster || true
sahara cluster-template-delete --name spark-cluster-template || true
sahara node-group-template-delete --name spark-master-tmpl || true
sahara node-group-template-delete --name spark-worker-tmpl || true

# master node template
cat >./tmp/ng_master_template_create.json <<EOL
{
    "name": "spark-master-tmpl",
    "flavor_id": "2",
    "plugin_name": "spark",
    "hadoop_version": "1.0.0",
    "node_processes": ["master", "namenode"],
    "auto_security_group": false 
}
EOL

sahara node-group-template-create --json ./tmp/ng_master_template_create.json
master_template_id=`sahara node-group-template-show --name spark-master-tmpl | awk '/ id / {print $4}'`

# worker node template
cat >./tmp/ng_worker_template_create.json <<EOL
{
    "name": "spark-worker-tmpl",
    "flavor_id": "2",
    "plugin_name": "spark",
    "hadoop_version": "1.0.0",
    "node_processes": ["slave", "datanode"],
    "auto_security_group": false
}
EOL

sahara node-group-template-create --json ./tmp/ng_worker_template_create.json
worker_template_id=`sahara node-group-template-show --name spark-worker-tmpl | awk '/ id / {print $4}'`

# cluster template
cat >./tmp/cluster_template_create.json <<EOL
{
    "name": "spark-cluster-template",
    "plugin_name": "spark",
    "hadoop_version": "1.0.0",
    "node_groups": [
        {
            "name": "master",
            "node_group_template_id": "${master_template_id}",
            "count": 1
        },
        {
            "name": "workers",
            "node_group_template_id": "${worker_template_id}",
            "count": 2
        }
    ]
}
EOL
sahara cluster-template-create --json ./tmp/cluster_template_create.json
cluster_template_id=`sahara cluster-template-show --name spark-cluster-template | awk '/ id / {print $4}'`

# provision cluster
image_id=`nova image-list | awk '/ sahara-juno-spark-1.0.0-ubuntu-14.04/ {print $2}'`
keypair=`nova keypair-list | awk 'NR==4 {print $2}'`
cat >./cluster_create.json <<EOL
{
    "name": "spark-cluster",
    "plugin_name": "spark",
    "hadoop_version": "1.0.0",
    "cluster_template_id" : "${cluster_template_id}",
    "user_keypair_id": "${keypair}",
    "default_image_id": "${image_id}"
}
EOL
sahara cluster-create --json cluster_create.json
