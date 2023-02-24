# @mtulio tools

- your IPv4

``` shell
curl https://mtulio.net/api/ip
```

- your IPv4 (json output)

``` shell
curl -s https://mtulio.net/api/ip/ip?json |jq .
```

``` json
{
  "ip": "1.2.3.4",
  "ipv4": "1.2.3.4"
}

```

- http echo

``` shell
curl -s https://mtulio.net/api/echo
```
- http echo (request headers)

``` shell
echo -e $(curl -s https://mtulio.eng.br/api/echo?1=2 |jq .headers)
```

```
"Content-Length: 0
Host: mtulio.eng.br
X-Forwarded-Host: mtulio.eng.br
Accept: */*
X-Vercel-Deployment-Url: mtulio-eng-br-9fz7hpsx5.vercel.app
X-Forwarded-Proto: https
X-Forwarded-For: 1.2.3.4
User-Agent: curl/7.61.1
X-Vercel-Forwarded-For: 1.2.3.4
X-Real-Ip: 1.2.3.4
X-Vercel-Id: gru1::x
```

<!--
- ping-go

```bash
curl https://mtulio.eng.br/api/ping-go
```

- ping-js

```bash
curl https://mtulio.eng.br/api/ping-js
```

- ping-go

```bash
curl https://mtulio.eng.br/api/ping-py
```

- py-async

```bash
curl https://mtulio.eng.br/api/py-async
```

-->

