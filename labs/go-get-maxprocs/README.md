# GOMAXPROCS usage lab

Experimental lab to change the number of cores used to go app

```
$ bash run.sh 

#> Check the default MaxProcs on Go runtime: 
GOMAXPROCS is 12

#> Setting to use NCores-1(11), and check the Go runtime: 
GOMAXPROCS is 11

#> Setting to use 50% of Cores (6), and check the Go runtime: 
GOMAXPROCS is 6
```

## References
- https://pkg.go.dev/runtime#GOMAXPROCS
- 
