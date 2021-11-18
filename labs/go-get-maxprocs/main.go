package main

import (
    "runtime"
    "fmt"
)

func getGOMAXPROCS() int {
    return runtime.GOMAXPROCS(0)
}

func main() {
    fmt.Printf("GOMAXPROCS is %d\n", getGOMAXPROCS())
}
