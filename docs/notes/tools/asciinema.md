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

## Tool: asciinema-edit

Project: https://github.com/cirocosta/asciinema-edit

- install

```
go get -u -v github.com/cirocosta/asciinema-edit
```

- cut some parts of the cast

```
asciinema-edit cut \
    --start=564.732 --end=5004.864 \
    opct-demo-01-run-02.cast > opct-demo-01-run-03.cast
```

- speed up some parts of the cast

```
asciinema-edit speed \
    --factor 10 --start=55.995835 --end=249.623772 \
    opct-demo-01-run-04.cast > opct-demo-01-run-05.cast
```

## Reference

- https://asciinema.org/
