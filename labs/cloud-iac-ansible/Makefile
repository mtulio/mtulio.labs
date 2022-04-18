
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
