#!/bin/sh

set -e

# Set your environment variables here
RHDG_OPERATOR_NAMESPACE=rhdg8-operator
RHDG_NAMESPACE=my-rhdg8
GRAFANA_NAMESPACE=grafana


#############################
## Do not modify anything from this line
#############################

# Print environment variables
echo -e "\n=============="
echo -e "ENVIRONMENT VARIABLES:"
echo -e " * RHDG_OPERATOR_NAMESPACE: $RHDG_OPERATOR_NAMESPACE"
echo -e " * RHDG_NAMESPACE: $RHDG_NAMESPACE"
echo -e " * GRAFANA_NAMESPACE: $GRAFANA_NAMESPACE"
echo -e "==============\n"


# Check if the user is logged in 
if ! oc whoami &> /dev/null; then
    echo -e "Check. You are not logged out. Please log in and run the script again."
    exit 1
else
    echo -e "Check. You are correctly logged in. Continue..."
    oc project default # To avoid issues with deleted projects
fi



# Delete projects

if oc get project $RHDG_OPERATOR_NAMESPACE &> /dev/null; then
    echo -e "\n[1/8]Removing the RHDG operator project"
    oc delete project $RHDG_OPERATOR_NAMESPACE
fi

if oc get project $RHDG_NAMESPACE &> /dev/null; then
    echo -e "\n[1/8]Removing the RHDG cluster project"
    oc delete project $RHDG_NAMESPACE
fi

if oc get project $RHDG_NAMESPACE &> /dev/null; then
    echo -e "\n[1/8]Removing the Grafana project"
    oc delete project $GRAFANA_NAMESPACE
fi

