
VENV_PATH ?= ./.venv
VENV_REQ ?= docs/requirements.txt

.PHONY: venv
venv:
	test -d $(VENV_PATH) || python3 -m venv $(VENV_PATH)

.PHONY: requirements
requirements: venv
	$(VENV_PATH)/bin/pip3 install --upgrade pip
	$(VENV_PATH)/bin/pip3 install -r $(VENV_REQ)

# Vercel
.PHONY: ci-dependencies
ci-dependencies:
	cat /etc/os-release
	yum install -y python3-pip graphviz

.PHONY: ci-install
ci-install: ci-dependencies requirements

mkdocs-serve:
	$(VENV_PATH)/bin/mkdocs serve

mkdocs-build:
	$(VENV_PATH)/bin/mkdocs build
