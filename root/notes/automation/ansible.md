# Ansible

## Install

### Virtualenv (python)

Python virtual environment is highly recommended to isolate the python packages in shared systems and avoid broken dependencies when projects needs specific packages/versions.


To use python virtual environment (recommended when using many ansible projects) you need to install the base python package on your system (need elevated permissions - `sudo`):


- Install using the System's package manager:
```bash
sudo dnf install python3-virtualenv
```

- Install using python3 package management (pip3):

```bash
sudo pip3 install virtualenv
```

- Create the virtuale environment

> in general `.venv` is the default virtualenvironemnt that resides in the same directory of the project that the virtualenv will be used (ex. dir `my-project`)

```bash
python3 -m venv my-project/.venv
```

- Enter in the project's directory and enable the virtual environment

```bash
cd my-project && \
source .venv/bin/activate
```

> NOTE1: the terminal should have a prefix (`(.venv)`) indicating that the venv is enabled, like that:

```bash
(.venv) [me@localhost .my-project]$ 
```

> NOTE2: all the python environment should be behind the path `.venv`, you can see the new path of pip:
```bash
which pip3
# OR just pip (ur new environment has default py interpreter py3, so both are version 3)
which pip
```


- Install the Ansible OR use requirements.txt file to persiste packages w/ versions

1. ad-hoc install
```bash
pip3 install ansible
```

2. `requirements.txt` file

requirements.txt content:
```bash
ansible>=2.9,<2.10
```

install

```bash
pip3 install -r requirements
```

### Container

To use ansible in a container, just use the same strategy of python virtual environment isolated.

There is two ways:
- install dependencies directly on `Dockerfile`, OR
- create a `requirements.txt` file with it's dependencies (highly recommended)

1. Create `Dockerfile`

a) Create `Dockerfile` with `requirements.txt` file:
```Dockerfile
FROM centos:latest
WORKDIR /ansible
COPY requirements.txt .
RUN yum -y install python3-pip && \
    pip3 install -r requirements.txt
```

b) OR, leave all dependences inside `Dockerfile`:
```Dockerfile
FROM centos:latest
WORKDIR /ansible
COPY requirements.txt .
RUN yum -y install python3-pip && \
    pip3 install ansible
```

2. Build the image

```bash
sudo podman build -t ansible .
```


3. Run the container w/ ad-hoc command `ping`

```bash
sudo podman run -v $PWD:/ansible -it ansible ansible localhost -m ping
```

## References

* [Main ansible 'how-to'](https://github.com/mtulio/ansible-infra/blob/master/HOWTO.md)

