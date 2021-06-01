# Shell Ops


## String operations

* Split string 

```
${var#*SubStr}  # will drop begin of string up to first occur of `SubStr`
${var##*SubStr} # will drop begin of string up to last occur of `SubStr`
${var%SubStr*}  # will drop part of string from last occur of `SubStr` to the end
${var%%SubStr*} # will drop part of string from first occur of `SubStr` to the end
```
