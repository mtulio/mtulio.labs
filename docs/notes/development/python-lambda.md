# Python LAMBDA

Syntax: `lambda argument_list: expression`

## basic

```python
In [1]: f = lambda x, y : x + y
In [2]: f(1, 1)
Out[2]: 2

```

## map()

```python
In [7]: l = [1, 2, 3]
In [8]: r = map(lambda x: x*x, l)
In [9]: print r
[1, 4, 9]
```

## filter()

```python
In [10]: l = [{'name': 'a', 'id':1}, {'name': 'b', 'id':2}]
In [12]: r = filter(lambda x: x['name'] == 'a', l)
In [13]: print r
[{'name': 'a', 'id': 1}]

```

## reduce()



* Refs: http://www.python-course.eu/lambda.php
