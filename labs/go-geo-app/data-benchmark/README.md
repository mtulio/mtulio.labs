
Results from:
```
LOCATION=$(curl -s ${APP_URL_NYC} |jq -r '.clientInfo.geoIP| ( .countryCode + "-" + .region )')
FILE_OUT="curl_${LOCATION}.txt"
> ${FILE_OUT}

echo "APP_URL_MAIN: " | tee -a ${FILE_OUT}
curl_batch "${APP_URL_MAIN}" | tee -a ${FILE_OUT}

echo "APP_URL_MAIN: " | tee -a ${FILE_OUT}
curl_batch "${APP_URL_NYC}" | tee -a ${FILE_OUT}

echo "APP_URL_MAIN: " | tee -a ${FILE_OUT}
curl_batch "${APP_URL_NYC}" | tee -a ${FILE_OUT}

```
