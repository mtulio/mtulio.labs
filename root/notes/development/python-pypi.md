# Python Pypi

## Publishing an module

* Pypi credentials

```shell
[distutils]
index-servers =
  pypi
  pypitest

[pypi]
repository=https://pypi.python.org/pypi
username=username
password=password

[pypitest]
repository=https://testpypi.python.org/pypi
username=username
password=password

```

* setup.py

```shell
from distutils.core import setup
setup(
  name = 'mypackage',
  packages = ['mypackage'], # this must be the same as the name above
  version = '0.1',
  description = 'A random test lib',
  author = 'Peter Downs',
  author_email = 'peterldowns@gmail.com',
  url = 'https://github.com/peterldowns/mypackage', # use the URL to the github repo
  download_url = 'https://github.com/peterldowns/mypackage/archive/0.1.tar.gz', # I'll explain this in a second
  keywords = ['testing', 'logging', 'example'], # arbitrary keywords
  classifiers = [],
)
```

* setup.cfg

```shell
[metadata]
description-file = README.md
```

* publish to test server

```shell
python setup.py register -r pypitest

python setup.py sdist upload -r pypitest
```

## Using TWINE

* Package module

`python setup.py sdist`

* Install TWINE

`pip install twine`

* Upload to PyPi

`twine upload dist/*`

## *References*:

* [PyPi](https://pypi.org)
* [PyPi test](https://testpypi.python.org/pypi)
* [First time with Pypi](http://peterdowns.com/posts/first-time-with-pypi.html)
