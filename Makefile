
VENV_PATH ?= ./.venv
VENV_REQ ?= requirements.txt

.PHONY: venv
venv:
	test -d $(VENV_PATH) || python3 -m venv $(VENV_PATH)

.PHONY: requirements
requirements: venv
	$(VENV_PATH)/bin/pip3 install --upgrade pip
	$(VENV_PATH)/bin/pip3 install -r $(VENV_REQ)

mkdocs-serve: requirements
	$(VENV_PATH)/bin/mkdocs serve

mkdocs-build: requirements
	$(VENV_PATH)/bin/mkdocs build
