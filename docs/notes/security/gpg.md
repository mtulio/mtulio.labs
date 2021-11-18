# gpg

Manage gpg keys.

## generate

gpg --default-new-key-algo rsa4096 --gen-key

## List

gpg --list-secret-keys --keyid-format=long


## Export

gpg --armor --export 3AA5C34371567BD2

## Use on git

https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key

```
$ git config --global user.signingkey 3AA5C34371567BD2

```

To add your GPG key to your bash profile, run the following command:

```
$ if [ -r ~/.bash_profile ]; then echo 'export GPG_TTY=$(tty)' >> ~/.bash_profile; \
  else echo 'export GPG_TTY=$(tty)' >> ~/.profile; fi
```

## Referebces

https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key