
VENV ?= ./.venv

venv:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -r requirements.txt

update:
	git submodule update --init --recursive
.PHONY: update

create-network:
	$(VENV)/bin/ansible-playbook net-create.yaml \
		-e provider=$(PROVIDER) -e name=$(NET_NAME)
.PHONY: create-network

k8s-create-network-aws-use1:
	$(MAKE) create-network PROVIDER=aws NET_NAME=k8s
.PHONY: k8s-create-network-aws-use1

k8s-create-network-aws-usw2:
	$(MAKE) create-network PROVIDER=aws NET_NAME=k8s-usw2
.PHONY: k8s-create-network-aws-usw2

k8s-create-master-aws:
	$(VENV)/bin/ansible-playbook run-instance.yaml \
		-e provider=aws -e name=k8s-masters
.PHONY: k8s-create-master-aws

gen-fcos-userdata:
	$(VENV)/bin/ansible-playbook fcos_config_gen.yaml \
		-e install_dir=$(PWD)/.install-dir-fcos
.PHONY: gen-fcos-userdata

machine-create-fcos-aws:
	$(VENV)/bin/ansible-playbook run-instance.yaml -vvv \
		-e provider=aws -e name=fcos \
		-e install_dir=$(PWD)/.install-dir-fcos
.PHONY: machine-create-fcos-aws

#### OPENSHIFT
INSTALL_DIR ?= $(PWD)/.install-dir-ocp
BOOTSTRAP_NAME ?= ocp-bootstrap
CONTROLPLANE_NAME ?= ocp-controlplane
openshift-config:
	$(VENV)/bin/ansible-playbook openshift_config_gen.yaml -vvv \
		-e provider=aws -e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-config

# Network stack
# - VPC
# - SG
openshift-stack-network:
	$(VENV)/bin/ansible-playbook net-create.yaml \
		-e provider=aws -e name=ocp \
		-e region=default \
		-e install_dir=$(INSTALL_DIR) \
		-e security_groups=[]
.PHONY: openshift-stack-network

openshift-stack-securitygroups:
	$(VENV)/bin/ansible-playbook net-create.yaml -vvv \
		-e provider=aws -e name=ocp \
		-e region=default \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-stack-securitygroups

# - DNS
openshift-stack-dns:
	$(VENV)/bin/ansible-playbook openshift_stack_dns.yaml -vvv \
		-e provider=aws -e name=ocp \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-stack-dns

# - NLB
openshift-stack-loadbalancers:
	$(VENV)/bin/ansible-playbook openshift_stack_loadbalancers.yaml -vvv \
		-e provider=aws -e name=ocp \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-stack-loadbalancers

# IAM
openshift-stack-iam:
	$(VENV)/bin/ansible-playbook openshift_stack_iam.yaml -vvv \
		-e provider=aws -e name=ocp \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-stack-iam

# S3 Bucket

# EC2: Bootstrap
openshift-bootstrap-setup:
	$(VENV)/bin/ansible-playbook openshift_create_bootstrap_setup.yaml -vvv \
		-e provider=aws -e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-bootstrap-setup

openshift-stack-compute-bootstrap: openshift-bootstrap-setup
	$(VENV)/bin/ansible-playbook openshift_create_bootstrap.yaml -vvv \
		-e provider=aws -e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-stack-compute-bootstrap

openshift-stack-compute-controlplane: openshift-bootstrap-setup
	$(VENV)/bin/ansible-playbook openshift_create_controlplane.yaml -vvv \
		-e provider=aws -e name=$(CONTROLPLANE_NAME) \
		-e install_dir=$(INSTALL_DIR)
.PHONY: openshift-stack-compute-controlplane


# EC2: Control Plane

# EC2: Compute

# All
openshift-install: openshift-config openshift-stack-iam openshift-stack-network openshift-stack-securitygroups openshift-stack-dns openshift-stack-loadbalancers openshift-stack-compute-controlplane openshift-stack-compute-bootstrap
.PHONY: openshift-install

get-console-output:
	aws ec2 get-console-output \
		--instance-id $(INSTANCE_ID) \
		| jq -r .Output |tee /tmp/console.log
.PHONY: get-console-output
