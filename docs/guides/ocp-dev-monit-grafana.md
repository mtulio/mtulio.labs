# OpenShift Monitoring Grafana Dashboard

Tutorial to use custom Grafana Dashboard to explore OpenShift metrics from a Prometheus Datasource.

This guide will use OpenShift CI jobs, exploring the exported Prometheus dump from CI e2e job using the Prometheus API exposed by PromeCleus.

Steps to use custom grafana:

## Restore the Promethes datasource

- Find the Prow job
- Click in the lens "Debug Tools", then [PromeCleus](https://promecieus.dptools.openshift.org/?search=)
- Paste the Job URL
- Open the Prometheus instance, and copy the URL (without path) saving for later usage

## Deploy Grafana Instance

- Create the Grafana Instance (skip if you already have one)

> https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/
> https://hub.docker.com/r/grafana/grafana

```sh
podman run -d --name=grafana -p 3000:3000 grafana/grafana
```

- Create or update a [Prometheus datasource](http://localhost:3000/connections/datasources) named `prometheus`
- Paste the PromeCleus URL (without path)
- Import the [Dashboard JSON file grafana-dashboard-promecleus.json](
https://raw.githubusercontent.com/mtulio/mtulio.labs/master/labs/ocp-grafana-dash/grafana-dashboard-promecleus.json)
- Adjust the Dashboard timeframe for your job execution and be happy.

Example:

<a href="https://github.com/mtulio/mtulio.labs/assets/3216894/985cecc9-e5d5-48e9-b8ee-a8c3aa6c0dd1">
    <img title="An example of OpenShift deployment metrics while running e2e on AWS"
         alt="OpenShift Dashboard"
         src="https://github.com/mtulio/mtulio.labs/assets/3216894/985cecc9-e5d5-48e9-b8ee-a8c3aa6c0dd1">
</a>
