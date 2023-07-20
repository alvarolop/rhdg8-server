#!/bin/sh

set -e

# Set your environment variables here
RHDG_OPERATOR_NAMESPACE=rhdg8-operator
RHDG_NAMESPACE=rhdg8
RHDG_CLUSTER_NAME=rhdg
GRAFANA_NAMESPACE=grafana
GRAFANA_DASHBOARD_NAME="dashboard-rhdg8"
GRAFANA_DASHBOARD_KEY="dashboard.json"
RHDG_AUTH_ENABLED=true
RHDG_SSL_ENABLED=false

#############################
## Do not modify anything from this line
#############################

# Print environment variables
echo -e "\n=============="
echo -e "ENVIRONMENT VARIABLES:"
echo -e " * RHDG_OPERATOR_NAMESPACE: $RHDG_OPERATOR_NAMESPACE"
echo -e " * RHDG_NAMESPACE: $RHDG_NAMESPACE"
echo -e " * RHDG_CLUSTER_NAME: $RHDG_CLUSTER_NAME"
echo -e " * GRAFANA_NAMESPACE: $GRAFANA_NAMESPACE"
echo -e " * GRAFANA_DASHBOARD_NAME: $GRAFANA_DASHBOARD_NAME"
echo -e " * RHDG_AUTH_ENABLED: $RHDG_AUTH_ENABLED"
echo -e " * RHDG_SSL_ENABLED: $RHDG_SSL_ENABLED"
echo -e "==============\n"

if ! $RHDG_AUTH_ENABLED; then
    OCP_CLUSTER_TEMPLATE="rhdg-02-cluster-basic"
    SERVICE_MONITOR_HTTP_SCHEME="http"
else 
    if ! $RHDG_SSL_ENABLED; then
        OCP_CLUSTER_TEMPLATE="rhdg-02-cluster-auth"
        SERVICE_MONITOR_HTTP_SCHEME="http"
    else
        OCP_CLUSTER_TEMPLATE="rhdg-02-cluster-auth-ssl"
        SERVICE_MONITOR_HTTP_SCHEME="https"
    fi
fi

# Check if the user is logged in 
if ! oc whoami &> /dev/null; then
    echo -e "Check. You are not logged out. Please log in and run the script again."
    exit 1
else
    echo -e "Check. You are correctly logged in. Continue..."
    if ! oc project &> /dev/null; then
        echo -e "Current project does not exist, moving to project Default."
        oc project default 
    fi
fi


##
# 0) MONITORING SET UP
## 
echo -e "\n[0/8]Configuring User Workload Monitoring"
oc apply -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/ocp-monitoring/10-cm-cluster-monitoring-config.yaml
oc apply -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/ocp-monitoring/11-cm-user-workload-monitoring-config.yaml

##
# 1) RHDG
## 

# Deploy the RHDG operator
echo -e "\n[1/8]Deploying the RHDG operator"
oc process -f rhdg-operator/rhdg-01-operator.yaml \
    -p OPERATOR_NAMESPACE=$RHDG_OPERATOR_NAMESPACE \
    -p CLUSTER_NAMESPACE=$RHDG_NAMESPACE | oc apply -f -

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l "app.kubernetes.io/name=infinispan-operator" -n $RHDG_OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Deploy the RHDG cluster
echo -e "\n[2/8]Deploying the RHDG cluster"
oc process -f rhdg-operator/${OCP_CLUSTER_TEMPLATE}.yaml \
    -p CLUSTER_NAMESPACE=$RHDG_NAMESPACE \
    -p CLUSTER_NAME=$RHDG_CLUSTER_NAME | oc apply -f -

# Create basic caches
echo -e "\n[3/8]Creating basic caches"
oc process -f rhdg-operator/rhdg-03-caches.yaml \
    -p CLUSTER_NAMESPACE=$RHDG_NAMESPACE \
    -p CLUSTER_NAME=$RHDG_CLUSTER_NAME | oc apply -f -

oc project $RHDG_NAMESPACE

##
# 2) PROMETHEUS
## 

# Configure Prometheus to monitor RHDG
echo -e "\n[4/8]Configure Prometheus to monitor RHDG"
oc process -f rhdg-operator/rhdg-04-monitoring.yaml \
    -p CLUSTER_NAMESPACE=$RHDG_NAMESPACE \
    -p CLUSTER_NAME=$RHDG_CLUSTER_NAME \
    -p SERVICE_MONITOR_HTTP_SCHEME=$SERVICE_MONITOR_HTTP_SCHEME | oc apply -f -


##
# 3) GRAFANA
## 

# Deploy the Grafana Operator
echo -e "\n[5/8]Deploying the Grafana operator"
oc process -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/grafana/10-operator.yaml \
    -p OPERATOR_NAMESPACE=$GRAFANA_NAMESPACE | oc apply -f -

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l control-plane=controller-manager -n $GRAFANA_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Create a Grafana instance
echo -e "\n[6/8]Creating a grafana instance"
oc process -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/grafana/20-instance.yaml \
    -p OPERATOR_NAMESPACE=$GRAFANA_NAMESPACE | oc apply -f -

echo -n "Waiting for ServiceAccount ready..."
while ! oc get sa grafana-sa -n $GRAFANA_NAMESPACE &> /dev/null; do   echo -n "." && sleep 1; done; echo -n -e " [OK]\n"

# --- In OCP 4.11 or higher ---
# Reason: https://access.redhat.com/solutions/2972601
# We don't use the `oc create token` as this token expires after 15m
BEARER_TOKEN=$(oc get secret $(oc describe sa grafana-sa -n $GRAFANA_NAMESPACE | awk '/Tokens/{ print $2 }') -n $GRAFANA_NAMESPACE --template='{{ .data.token | base64decode }}')

# Create a Grafana datasource
echo -e "\n[7/8]Creating the Grafana data source"
oc process -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/grafana/30-datasource.yaml \
    -p BEARER_TOKEN=$BEARER_TOKEN \
    -p OPERATOR_NAMESPACE=$GRAFANA_NAMESPACE | oc apply -f -

# Create the default Grafana dashboard created by the operator
echo -e "\n[8/8]Creating the default Grafana dashboard"

oc process -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/grafana/40-dashboard.yaml \
  -p DASHBOARD_GZIP="$(cat grafana/grafana-default-operator-dashboard.json | gzip | base64 -w0)" \
  -p DASHBOARD_NAME=${GRAFANA_DASHBOARD_NAME}-default | oc apply -f -

# Create an extra Grafana dashboard
echo -e "\n[8/8]Creating the custom Grafana dashboard"

oc process -f https://raw.githubusercontent.com/alvarolop/quarkus-observability-app/main/openshift/grafana/40-dashboard.yaml \
  -p DASHBOARD_GZIP="$(cat grafana/grafana-dashboard-rhdg8.json | gzip | base64 -w0)" \
  -p DASHBOARD_NAME=${GRAFANA_DASHBOARD_NAME}-custom | oc apply -f -

# Print Grafana credentials
GRAFANA_ADMIN=$(oc get secret grafana-admin-credentials -n $GRAFANA_NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 --decode)
GRAFANA_PASSW=$(oc get secret grafana-admin-credentials -n $GRAFANA_NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 --decode)
GRAFANA_ROUTE=$(oc get routes -l app=grafana -n $GRAFANA_NAMESPACE --template='https://{{(index .items 0).spec.host }}')

echo -e "\nGrafana log in information:"
echo -e " * User / Password: $GRAFANA_ADMIN / $GRAFANA_PASSW"
echo -e " * URL: $GRAFANA_ROUTE"

