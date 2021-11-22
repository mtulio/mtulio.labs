#!/usr/bin/env bash

echo -e "\n#> Check the default MaxProcs on Go runtime: "
go run main.go

USE_MAX_PROC=$(echo "$(nproc) - 1 " |bc)
echo -e "\n#> Setting to use NCores-1(${USE_MAX_PROC}), and check the Go runtime: "
GOMAXPROCS=${USE_MAX_PROC} go run main.go

USE_MAX_PROC=$(echo "$(nproc) / 2 " |bc)
echo -e "\n#> Setting to use 50% of Cores (${USE_MAX_PROC}), and check the Go runtime: "
GOMAXPROCS=${USE_MAX_PROC} go run main.go
