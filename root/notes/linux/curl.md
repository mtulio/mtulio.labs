# curl

Yeap, curl deserves an entire file to show it's options

## GET

* Make me serial requests

`X=0; while true; do echo -n "$X ";curl  http://localhost/; echo; let "X++"; done`

* Show me only status code from an request

`curl -o /dev/null -I -sw "%{http_code}" http://localhost/ `

## Pretty stdout

### Basic

1) create the `curl-format.txt` file with these content:

```
  time_namelookup:  %{time_namelookup} Sec\n
      time_connect:  %{time_connect} Sec\n
   time_appconnect:  %{time_appconnect} Sec\n
  time_pretransfer:  %{time_pretransfer} Sec\n
     time_redirect:  %{time_redirect} Sec\n
time_starttransfer:  %{time_starttransfer} Sec\n
                   ----------\n
        time_total:  %{time_total} Sec\n
```

2) Run the command:

```shell
curl -w "@curl-format.txt" -o /dev/null -s https://www.google.com/test.txt
```
### Advanced

So, let's automate it creating an alias to be easy to use in emergencies. :)

1) create the text file, for ex. `~/bin/curl-format.txt`, with stdout arguments to be show.

```text
\n# Request\n
          url_effective: %{url_effective}\n
           content_type: %{content_type}\n
     filename_effective: %{filename_effective}\n
               local_ip: %{local_ip}\n
# Response\n
              remote_ip: %{remote_ip}\n
            remote_port: %{remote_port}\n
                 scheme: %{scheme}\n
              http_code: %{http_code}\n
           http_connect: %{http_connect}\n
           http_version: %{http_version}\n
           num_connects: %{num_connects}\n
          num_redirects: %{num_redirects}\n
proxy_ssl_verify_result: %{proxy_ssl_verify_result}\n
           redirect_url: %{redirect_url}\n
      ssl_verify_result: %{ssl_verify_result}\n
##-> Response sizes \n
          size_download: %{size_download} Bytes\n
            size_header: %{size_header} Bytes\n
           size_request: %{size_request} Bytes\n
            size_upload: %{size_upload} Bytes\n
         speed_download: %{speed_download} Bytes/sec\n
           speed_upload: %{speed_upload} Bytes/sec\n
##-> Response Times\n
        time_namelookup: %{time_namelookup} Sec\n
           time_connect: %{time_connect} Sec\n
        time_appconnect: %{time_appconnect} Sec\n
       time_pretransfer: %{time_pretransfer} Sec\n
          time_redirect: %{time_redirect} Sec\n
     time_starttransfer: %{time_starttransfer} Sec\n
                   ----------\n
             time_total: %{time_total} Sec\n
\n

```

2) Create the alias to use the cUrl. Open ~/.bashrc:

```bash
# cURL
#https://curl.haxx.se/docs/manpage.html
CURL_FORMAT=~/bin/curl-format.txt
alias curl-debug-verbose="curl -w \"@${CURL_FORMAT}\" -o /dev/null -s "
```

3) test it to see an verbose output

```bash
curl-debug-verbose 'https://www.google.com/test.txt'
```
