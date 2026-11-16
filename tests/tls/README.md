# TLS test certificates

Self-signed certificates and their private keys, made only for the tests'
TLS server on 127.0.0.1 (`Sloper.Tests.TlsServer`), with which
`Sloper.Tests.Assistant` checks that the assistant's HTTPS transport refuses
certificates it should not trust, and `Sloper.Tests.CLI` runs
`check-connection`.
They are not secret and must never be trusted anywhere else.

- `localhost.pem`, `localhost.key`: for `localhost`.
- `otherhost.pem`, `otherhost.key`: for `otherhost.test`, a name that is not
  `localhost`, so a trusted certificate for the wrong host is refused.

Made with, valid for 100 years:

```
openssl req -x509 -newkey rsa:2048 -nodes -keyout localhost.key -out localhost.pem \
  -days 36500 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
```
