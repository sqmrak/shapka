# trusted roots

`roots.pem` is curl's PEM conversion of the Mozilla root store, downloaded from `https://curl.se/ca/cacert.pem`. its header dates the source certificate data to 2026-10-20. the file's sha256 is `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`.

this is a trust store, not a certificate pin. certificate chain, validity dates and hostname are checked by openssl. refresh the file from curl's documented ca extract process when preparing an application update, review its contents and update this record. an already installed copy does not update itself.
