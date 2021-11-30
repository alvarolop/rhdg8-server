import os

os.system('oc apply -f rhdg-chart/secret/secret.yaml')
os.system('helm install rhdg8-helm openshift-helm-charts/infinispan-infinispan -f rhdg-chart/custom-user-values.yaml')