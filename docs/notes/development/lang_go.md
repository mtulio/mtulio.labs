# Go Lang

## Install


## Module

Common usage:

- vendoring/update local dependencies

```
go mod vendor
```

- getting pseudo-version from tag

```
git tag v1.67.0
git push origin v2.67.0

go list -m -json github.com/mtulio/terraform-provider-aws@v1.67.0
```

- getting pseudo-version from a branch

```
go get -d github.com/mtulio/terraform-provider-aws@release-2.67.0-add-gp3-valid
```

References:
- https://golang.org/ref/mod
- https://golang.org/ref/mod#go-mod-file-replace

## Runtime

### GOMAXPROCS

- [Lab changing GOMAXPROCS according the CPU used on the machine](https://github.com/mtulio/mtulio.labs/tree/master/labs/go-get-maxprocs#gomaxprocs-usage-lab)
