# Kubernetes Scale Validation

Simple way to create "workloads" (pause pods with fixed requests) to validate the
cluster scale up/down.

## Usage

- Deploy the base app

~~~sh
oc apply -k deploy-inflate/

oc get all -n lab-scaling
~~~

- Warm up the scale (deploy single pod):

~~~sh
oc apply -k overlay/inflate-00-up-1-1

oc get pods -n lab-scaling
~~~

- Inflate the cluster to 25 pods

~~~sh
oc apply -k overlay/inflate-00-up-25-25/

oc get pods -n lab-scaling -o wide -w
~~~

Check if there are nodes scaling:

~~~sh
oc get machines -n openshift-machine-api -w
oc get nodes
~~~

- Scale down to single replica:

~~~sh
oc apply -k overlay/inflate-00-up-1-1
~~~