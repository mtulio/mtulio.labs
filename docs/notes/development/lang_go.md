# Go Language | Development notes

## Install

ToDo

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

- getting pseudo-version from a branch:
```
# option 1)
go list -f '{{.Version}}' -m github.com/mtulio/library-go@tmp-promote-external

# option 2)
TZ=UTC git --no-pager show \
   --quiet \
   --abbrev=12 \
   --date='format-local:%Y%m%d%H%M%S' \
   --format="%cd-%h"

# option 3)
go get -d github.com/mtulio/terraform-provider-aws@release-2.67.0-add-gp3-valid
```

References:

- https://golang.org/ref/mod
- https://golang.org/ref/mod#go-mod-file-replace
- https://jfrog.com/blog/go-big-with-pseudo-versions-and-gocenter/

## Runtime

### GOMAXPROCS

- [Lab changing GOMAXPROCS according the CPU used on the machine](https://github.com/mtulio/mtulio.labs/tree/master/labs/go-get-maxprocs#gomaxprocs-usage-lab)


## Concurrency

- [Talk concurrency](https://go.dev/blog/io2013-talk-concurrency)
- [Blog/Producer-consumer](https://betterprogramming.pub/hands-on-go-concurrency-the-producer-consumer-pattern-c42aab4e3bd2)


## Best Practices

- [Google talks/Twelve Go Best Practices](https://talks.golang.org/2013/bestpractices.slide#1)


## Algorithms

### Leaky Bucket

- [Wikipedia definition](https://en.wikipedia.org/wiki/Leaky_bucket)
- [mtulio's labs Sample: AWS IAM Filter user](https://github.com/mtulio/go-labs/pull/4)
- [Go Play/Simple sample](https://go.dev/play/p/ZrTPLcdeDF)
