#!/bin/bash

COLLECTION_PATH=$(dirname $0)/../../../../ansible-collection-okd-installer
INSTALL_PATH=$(dirname $0)/../collections

test -d $COLLECTION_PATH || ( echo "$COLLECTION_PATH is not a directory"; exit 1 )

ls -l $COLLECTION_PATH
ls -l $INSTALL_PATH

ansible-galaxy collection install ${COLLECTION_PATH} -p ${INSTALL_PATH}

