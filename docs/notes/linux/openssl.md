# openssl


* Convert PFX to PEM

`openssl pkcs12 -in certificate.pfx -out certificate.cer -nodes`

* Extracting Certificate and Private Key Files from a .pfx File

openssl pkcs12 -in cert.pfx -nocerts -out cert.key.pem -nodes

* Run the following command to export the certificate: 

`openssl pkcs12 -in certname.pfx -nokeys -out cert.pem`

* Run the following command to remove the passphrase from the private key: 

`openssl rsa -in key.pem -out server.key`
