# openssl


* Convert PFX to PEM

`openssl pkcs12 -in certificate.pfx -out certificate.cer -nodes`

* Extracting Certificate and Private Key Files from a .pfx File

openssl pkcs12 -in cert.pfx -nocerts -out cert.key.pem -nodes

* Run the following command to export the certificate: 

`openssl pkcs12 -in certname.pfx -nokeys -out cert.pem`

* Run the following command to remove the passphrase from the private key: 

`openssl rsa -in key.pem -out server.key`

## x509

- View the cert
```bash
openssl x509 -in /etc/etcd/kubernetes.pem -text -noout
```

- check the issuer and subject

```bash
cat <cert_file> | openssl x509 -text -noout |egrep '(Issuer|Subject)'
```
