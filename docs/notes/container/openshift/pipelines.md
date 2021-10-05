# OpenShift Pipelines


## Usage

### Sample setup

- Install tkn cli

~~~
wget https://mirror.openshift.com/pub/openshift-v4/clients/pipeline/0.13.1/tkn-linux-amd64-0.13.1.tar.gz
tar xvfz tkn-linux-amd64-0.13.1.tar.gz
~~~

- Setup operator
~~~
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: ocp-4.6
  name: openshift-pipelines-operator-rh 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace 
EOF

oc get events -n openshift-operators
oc get all -n openshift-pipelines
~~~

- Create a project
~~~
oc new-project my-pipelines
oc get serviceaccount pipeline
~~~

- Deploy a sample task

~~~
oc create -f https://raw.githubusercontent.com/openshift/pipelines-tutorial/release-tech-preview-3/01_pipeline/01_apply_manifest_task.yaml
oc create -f https://raw.githubusercontent.com/openshift/pipelines-tutorial/release-tech-preview-3/01_pipeline/02_update_deployment_task.yaml
tkn task list
~~~

- Create pipeline

~~~
oc create -f ./labs/pipeline.yaml
~~~

- Continue to run
https://docs.openshift.com/container-platform/4.6/pipelines/creating-applications-with-cicd-pipelines.html


## Scripts

### Backup

- file:backup-pipelines.sh 
~~~
BACKUP_DIR_LOCAL=data_collected/backup-pipelines
mkdir -p ${BACKUP_DIR_LOCAL}

PROJECTS=$(oc get projects --no-headers  -o jsonpath='{.items[*].metadata.name}')
echo ${PROJECTS} > ${BACKUP_DIR_LOCAL}/projects.list

for PROJECT in ${PROJECTS}; do
  PROJ_PATH=${BACKUP_DIR_LOCAL}/${PROJECT} ;
  mkdir -p ${PROJ_PATH} ;
  tkn task list -n ${PROJECT} &> ${PROJ_PATH}/task.list ;
  tkn taskrun list -n ${PROJECT} &> ${PROJ_PATH}/taskrun.list ;
  tkn pipelines list -n ${PROJECT} &> ${PROJ_PATH}/pipelines.list ;
  tkn pipelinerun list -n ${PROJECT} &> ${PROJ_PATH}/pipelinerun.list ;

  TK_OUT=${PROJ_PATH}/tasks.out
  for TASK in $(tkn tasks list -o json |jq .items[].metadata.name |tr -d '"'); do echo -e "\n-> ${PROJECT} - Collecting ${TASK} " |tee -a  ${TK_OUT}; tkn tasks describe ${TASK} &>> ${TK_OUT} ; done

  TK_OUT=${PROJ_PATH}/pipelines.out
  for PP in $(tkn pipelines list -o json |jq .items[].metadata.name |tr -d '"'); do echo -e "\n-> ${PROJECT} - Collecting ${PP} " |tee -a  ${TK_OUT}; tkn pipeline describe ${PP} &>> ${TK_OUT} ; done
done
~~~
