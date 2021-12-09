# asciinema

## Install

``` bash
pip3 install asciinema
```

## Record

``` bash
asciinema rec ~/Downloads/test.cast
```

- Modify the speed of existing recorder

``` bash
asciinema rec -c 'asciinema play -s 4 ~/Downloads/test.cast' ~/Downloads/test-faster.cast
```

## Play locally

``` bash
asciinema play /home/mtulio/Downloads/rec-test
```

- change the speed (2x)

``` bash
asciinema play -s 2 /home/mtulio/Downloads/rec-test
```

## Upload

``` bash
asciinema upload /home/mtulio/Downloads/rec-test
```

## Reference

- https://asciinema.org/
