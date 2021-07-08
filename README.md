# release-sign
Tools and instructions for Github releases signing using the OpenPGP key(s).

## Key generation

First you'll need to generate strong enough OpenPGP key with email which corresponds to your repository/company name.
Following commands may be used, utilizing the RNP OpenPGP suite:  
`rnpkeys --generate --expert --userid "Dummy Release Signing <dummy@example.com>"`
Then you'll need to choose algorithm and curve for ECC or key size for the RSA/DSA keypairs.
EdDSA/X25519 or RSA 3072 and up would be good enough.
Also you may want to add `--homedir somedir` parameter so keys will be stored in a folder other then your global `${HOME}/.rnp` keystorage.

Once generation is finished, you'll get something like the following:
```
sec   3072/RSA (Encrypt or Sign) 2ba318771716f1c2 2021-07-01 [SC]
      91bd5489242b44def6cb633b2ba318771716f1c2
uid           Dummy Release Signing <dummy@example.com>
ssb   3072/RSA (Encrypt or Sign) bee55641c8403ae5 2021-07-01 [E]
      070139d64b594240141e6c18bee55641c8403ae5
```

You may get the same output again issuing the `--list-keys` command: `rnpkeys --homedir .rnp --list-keys`
Note text `sec` and `ssb` - this means that you have a secret key.
Hex digit blocks `2ba318771716f1c2` and `91bd5489242b44def6cb633b2ba318771716f1c2` are your keyid and key fingerprint - unique identifiers, which identify your key. Keyid is just rightmost 16 hex chars of the fingerprint.

Same can be done with GnuPG:
`gpg --full-generate-key --expert`, `--homedir` parameter apply here as well.

## Key publication

Once secret key is generated, you need to make public aware of your key, so people may use it to verify signatures.
First you should export public key part: `rnpkeys --homedir .rnp --export 2ba318771716f1c2 > release-key.asc`

Or via the GnuPG: `gpg --homedir .gpg --armor --export 2ba318771716f1c2 > release-key.asc`

Then it may be added to your distribution and/or uploaded to the keyserver like https://keys.openpgp.org/
Also key server and key's fingerprint should be mentioned in the release notes, so user may access key to verify signatures.

## Signing

Once new version is released, and tag is pushed to the GitHub, you'll be able to edit release's page on the GitHub, adding release notes and uploading artifacts. Also you'll be able to download a source tarball.

You may manually download sources, check whether archive corresponds to the latest commits, and sign it, however it is more handy to use `./rel-sign.sh` script, which will do everything for you (in the example code secret key is exported to the file):

`./rel-sign.sh --repo rnpgp/rnp -v 0.15.1 --pparams "--keyfile dummy-release-sec.asc"`

On success you'll receive line `Signatures are stored in files v0.15.1.tar.gz.asc and v0.15.1.zip.asc. `, and corresponding signature files.
Next you'll need to upload those signatures to the GitHub release artifacts section.

## Verification

To verify signature, having downloaded source tarball, you may use the following commands:
```
wget https://github.com/rnpgp/rnp/archive/refs/tags/v0.15.1.tar.gz
wget https://github.com/rnpgp/rnp/archive/refs/tags/v0.15.1.tar.gz.asc
rnp --keyfile dummy-release-pub.asc -v v0.15.1.tar.gz.asc
```

Output should be as following on success:
```
Good signature made Thu Jul  1 16:03:15 2021
using RSA (Encrypt or Sign) key 2ba318771716f1c2

pub   3072/RSA (Encrypt or Sign) 2ba318771716f1c2 2021-07-01 [SC]
      91bd5489242b44def6cb633b2ba318771716f1c2
uid           Dummy Release Signing <dummy@example.com>
Signature(s) verified successfully
```

In case of verification error some BAD Signature message would be printed.