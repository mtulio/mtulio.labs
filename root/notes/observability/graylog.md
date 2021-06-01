# Graylog (World)

## Graylog CLI

Project: https://github.com/globocom/glog-cli

### *INSTALL*

```bash
$ virtualenv venv-py && ./venv-py/bin/pip install glog-cli && ./venv-py/bin/activate
```

### *USAGE*

`glogcli "source:mysserver" -d --fields timestamp,level,message -f`

## Graylog CLI Dashboard

Project: https://github.com/graylog-labs/cli-dashboard

### *INSTALL*

* Create virtualenv

```bash
$ virtualenv venv-py && ./venv-py/bin/pip install nodeenv && ./venv-py/bin/activate
$ ./venv-py/bin/nodeenv venv-node && venv-node/bin/activate 
```

* Install it

```bash
$ git clone -r git@github.com:graylog-labs/cli-dashboard.git graylog-cli-dashboard && cd graylog-cli-dashboard
$ npm install
```

### *USAGE*

`nodejs graylog-dashboard.js --stream-title "Query" --server-url https://graylog.mydomain.com --poll-interval 2`
