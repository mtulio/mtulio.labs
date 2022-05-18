
VENV ?= ./.venv

venv:
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -r requirements.txt

update:
	git submodule update --init --recursive
.PHONY: update

create-network:
	$(VENV)/bin/ansible-playbook net-create.yaml \
		-e provider=$(PROVIDER) \
		-e name=$(NET_NAME) \
		$(EXTRA_ARGS)
.PHONY: create-network

k8s-create-network-aws-use1:
	$(MAKE) create-network \
		PROVIDER=aws \
		NET_NAME=k8s \
		EXTRA_ARGS="-e region=us-east-1"
.PHONY: k8s-create-network-aws-use1

k8s-create-network-aws-usw2:
	$(MAKE) create-network \
		PROVIDER=aws \
		NET_NAME=k8s-usw2
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
CONFIG_PROVIDER ?= aws
INSTALL_DIR ?= $(PWD)/.install-dir-ocp
BOOTSTRAP_NAME ?= ocp-bootstrap
CONTROLPLANE_NAME ?= ocp-controlplane
COMPUTE_NAME ?= ocp-compute
EXTRA_ARGS ?= 
OPENSHIFT_RELEASE=4.10.13
REGION ?= us-east-1
CONFIG_REGION ?= $(REGION)

openshift-install-clients:
	$(VENV)/bin/ansible-playbook openshift_install_clients.yaml -vvv \
		-e release_version=$(OPENSHIFT_RELEASE) \
		-e workdir=$(PWD)/.install-dir-bin \
		$(EXTRA_ARGS)
.PHONY: openshift-install-clients

openshift-config:
	$(VENV)/bin/ansible-playbook openshift_config_gen.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR) \
		-e workdir=$(PWD)/.install-dir-bin \
		$(EXTRA_ARGS)
.PHONY: openshift-config

openshift-config-load:
	$(VENV)/bin/ansible-playbook openshift_config_load.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-config-load

# Network stack
# - VPC
# - SG
openshift-stack-network:
	$(VENV)/bin/ansible-playbook openshift_stack_net.yaml \
		-e name=ocp \
		-e provider=$(CONFIG_PROVIDER) \
		-e region=$(REGION) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-network

# - DNS
openshift-stack-dns:
	$(VENV)/bin/ansible-playbook openshift_stack_dns.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=ocp \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-dns

# - NLB
openshift-stack-loadbalancers:
	$(VENV)/bin/ansible-playbook openshift_stack_loadbalancers.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=ocp \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-loadbalancers

## NLB for ingress on non-integrated platform (platform=none)
openshift-stack-loadbalancers-none:
	$(VENV)/bin/ansible-playbook openshift_stack_loadbalancers.yaml -vvv \
		-e provider=none-$(CONFIG_PROVIDER) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-loadbalancers-none

openshift-destroy-loadbalancers-none:
	$(VENV)/bin/ansible-playbook openshift_destroy_cluster.yaml -vvv \
		-e config=none-$(CONFIG_PROVIDER) \
		-e provider=$(CONFIG_PROVIDER) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-destroy-loadbalancers-none

# IAM
openshift-stack-iam:
	$(VENV)/bin/ansible-playbook openshift_stack_iam.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=ocp \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-iam

# S3 Bucket

# EC2: Bootstrap
openshift-bootstrap-setup:
	$(VENV)/bin/ansible-playbook openshift_create_bootstrap_setup.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-bootstrap-setup

openshift-stack-bootstrap:
	$(VENV)/bin/ansible-playbook openshift_create_bootstrap.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=$(BOOTSTRAP_NAME) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-bootstrap

# EC2: Control Plane
openshift-stack-controlplane: openshift-bootstrap-setup
	$(VENV)/bin/ansible-playbook openshift_create_node.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=$(CONTROLPLANE_NAME) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-controlplane

# EC2: Compute
openshift-stack-compute:
	$(VENV)/bin/ansible-playbook openshift_create_node.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e name=$(COMPUTE_NAME) \
		-e install_dir=$(INSTALL_DIR) $(EXTRA_ARGS)
.PHONY: openshift-stack-compute

# All
openshift-install: openshift-config openshift-stack-iam openshift-stack-network openshift-stack-dns openshift-stack-loadbalancers openshift-stack-controlplane openshift-stack-bootstrap openshift-stack-compute
.PHONY: openshift-install

## Infra
openshift-create-infra: openshift-config openshift-stack-iam openshift-stack-network openshift-stack-dns openshift-stack-loadbalancers
.PHONY: openshift-create-infra

openshift-create-controlplane: openshift-stack-controlplane openshift-stack-bootstrap
.PHONY: openshift-create-controlplane

## Destroy
openshift-destroy:
	$(VENV)/bin/ansible-playbook openshift_destroy_cluster.yaml -vvv \
		-e provider=$(CONFIG_PROVIDER) \
		-e install_dir=$(INSTALL_DIR) \
		$(EXTRA_ARGS)
.PHONY: openshift-destroy

clean:
	rm -rvf $(INSTALL_DIR)
.PHONY: clean

# Extra
get-console-output:
	aws ec2 get-console-output \
		--instance-id $(INSTANCE_ID) \
		| jq -r .Output |tee /tmp/console.log
.PHONY: get-console-output
