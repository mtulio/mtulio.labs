# go-geo-app

[![Docker Repository on Quay](https://quay.io/repository/mrbraga/go-geo-app/status "Docker Repository on Quay")](https://quay.io/repository/mrbraga/go-geo-app)


Simple Go application to get the Geo location from HTTP client (caller) IP.

This example app was used to post to research about running apps on AWS Local Zones using OpenShift.

## Install

The container is available on docker, you can use:

```bash
podman run -p 8000:8000 -d quay.io/mrbraga/go-geo-app:latest
```

## Usage

- Basic usage

> It might fail when your interface has no a valid Public IP. See the argument `ip`

`$ curl -s http://localhost:8000 |jq .`

- Get your Public IP Geo information

> Forcing my public IP address (gateway)

`$ curl -s http://localhost:8000/?ip=$(curl -s https://mtulio.net/api/ip) |jq .`
```json
{
  "as": "AS12345 TELEFÔNICA BRASIL S.A",
  "city": "Florianópolis",
  "country": "Brazil",
  "countryCode": "BR",
  "isp": "TELEFÔNICA BRASIL S.A",
  "lat": -27.5707056,
  "lon": -48.7504627,
  "org": "Global Village Telecom",
  "query": "191.190.191.190",
  "region": "SC",
  "regionName": "Santa Catarina",
  "status": "success",
  "timezone": "America/Sao_Paulo",
  "zip": "88000"
}
```

- Query a custom IP (1)

`$ curl -s http://localhost:8000/?ip=$(dig +short mtulio.net |tail -n1) |jq .`
```json
{
  "as": "AS16509 Amazon.com, Inc.",
  "city": "Walnut",
  "country": "United States",
  "countryCode": "US",
  "isp": "Amazon.com, Inc.",
  "lat": 34.0119,
  "lon": -117.86,
  "org": "Vercel, Inc",
  "query": "76.76.21.21",
  "region": "CA",
  "regionName": "California",
  "status": "success",
  "timezone": "America/Los_Angeles",
  "zip": "91789"
}
```

- Query a custom IP (2)

`$ curl -s http://localhost:8000/?ip=8.8.8.8 |jq .`
```json
{
  "as": "AS15169 Google LLC",
  "city": "Ashburn",
  "country": "United States",
  "countryCode": "US",
  "isp": "Google LLC",
  "lat": 39.03,
  "lon": -77.5,
  "org": "Google Public DNS",
  "query": "8.8.8.8",
  "region": "VA",
  "regionName": "Virginia",
  "status": "success",
  "timezone": "America/New_York",
  "zip": "20149"
}
```
