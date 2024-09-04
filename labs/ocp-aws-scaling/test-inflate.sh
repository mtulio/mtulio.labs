#!/bin/bash
#

function echo_date() {
  echo "$(date -u --rfc-3339=seconds) - $*"
}

export DESIRED=0

function scale() {
  echo_date "Starting scaling to $DESIRED"
  oc apply -k overlay/inflate-00-up-$DESIRED/

  echo_date "Wating until pods are running..."
  until oc wait --for=jsonpath=.status.availableReplicas=$DESIRED deployment.apps/inflate -n lab-scaling --timeout=15m
  do
    ready=$(oc get deployment.apps/inflate -n lab-scaling -o jsonpath='{.status.readyReplicas}')
    echo_date "Waiting for ready replicas...[$ready/$DESIRED]"
    sleep 10
  done

  ready=$(oc get deployment.apps/inflate -n lab-scaling -o jsonpath='{.status.readyReplicas}')
  echo_date "Ready $DESIRED finished, checking current replicas: $ready"
}

DESIRED=12
scale

sleep 

DESIRED=25
scale

DESIRED=0
scale