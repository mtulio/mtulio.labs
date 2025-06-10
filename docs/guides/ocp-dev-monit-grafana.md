# OpenShift Monitoring Grafana Dashboard

Tutorial to use custom Grafana Dashboard to explore OpenShift metrics from a Prometheus datasource.

This guide will use a Prometheus endpoint from an OpenShift CI job, exploring the exported Prometheus database from a OpenShift/Prow CI job using the Prometheus API exposed by PromeCIeus.

Steps to use custom grafana:

1) Restore the Prometheus datasource from a CI execution

- Find the Prow job
- Click in the lens "Debug Tools", then [PromeCIeus](https://promecieus.dptools.openshift.org/?search=)
- Paste the Job URL
- Click in Generate to restore the the Prometheus database to an instance
- Copy the URL (without path `/graph`) for later

2) Deploy Grafana Instance using PromeCIeus as Datasource

- Create the Grafana Instance (skip if you already have one)

> See also Grafana Container: https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/ https://hub.docker.com/r/grafana/grafana

```sh
podman run -d --name=grafana -p 3000:3000 grafana/grafana
```

- Open the Grafana creating a new [Prometheus datasource](http://localhost:3000/connections/datasources), **naming it as `prometheus`**.
- Paste the PromeCIeus URL (without path `/graph`. example: https://ntpvpgpq-promecieus.apps.cr.j7t7.p1.openshiftapps.com)
- Download the [Dashboard JSON file grafana-dashboard-promecleus.json](
https://raw.githubusercontent.com/mtulio/mtulio.labs/master/labs/ocp-grafana-dash/grafana-dashboard-promecleus.json), and [import to Grafana](http://localhost:3000/dashboard/import)
- Adjust the Dashboard timeframe for your job execution and be happy.

Example:

<a href="https://github.com/mtulio/mtulio.labs/assets/3216894/985cecc9-e5d5-48e9-b8ee-a8c3aa6c0dd1">
    <img title="An example of OpenShift deployment metrics while running e2e on AWS"
         alt="OpenShift Dashboard"
         src="https://github.com/mtulio/mtulio.labs/assets/3216894/985cecc9-e5d5-48e9-b8ee-a8c3aa6c0dd1">
</a>
