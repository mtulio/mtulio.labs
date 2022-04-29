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

## Automation

- Save a new cast 10x faster:

> file: record-fix.sh

`./record-fix.sh casts/my-slow-cast.cast 10`
```bash
REC_FILE=$1
REC_FILE_BASE="$(basename -s .cast $1)"
speed=${2:-4}
REC_FILE_NEW="./casts/${REC_FILE_BASE}-${speed}x.cast"

test -f ${REC_FILE} || exit 1

sed -is "s/go\/src\/github.com\/$(whoami)/-/" $REC_FILE
sed -is "s/$(hostname -s)/localhost/g" $REC_FILE
sed -is "s/$(whoami)/user/g" $REC_FILE

asciinema rec -c "asciinema play -s ${speed} $1" ${REC_FILE_NEW}
```

## Reference

- https://asciinema.org/
