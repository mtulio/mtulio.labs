# python Tips


## pycurl using different SSL lib

* Error:
`ImportError: pycurl: libcurl link-time ssl backend (nss) is different from compile-time ssl backend (none/other)`

* Solve:

```
pip uninstall pycurl
export PYCURL_SSL_LIBRARY=nss
pip install pycurl --no-cache-dir
```

* Refs:
1. https://stackoverflow.com/questions/21487278/ssl-error-installing-pycurl-after-ssl-is-set
