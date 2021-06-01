# python-basic

Basic operations in Python


## loops

* for - common map iterator

```
res = 0
for x in '1 2 3':
  res += x
print "Sum is {}".format(res)
```

* for - inline
> syntax: `val = [thing for thing in list_of_things]`
```
matrix = [1, 2, 3]
print "ELements of matrix * 2 is: {}".format([x * 2 for x in matrix])
```

* for - range elements

`for x in range(0, 3): print x`


## input/output

* read an string stream, parse to int and print

> Ex. input: '0 3 1'
```
a0, a1, a2 = raw_input().strip().split(' ')
a0, a1, a2 = [int(a0), int(a1), int(a2)]
print a0, a1, a2
```


