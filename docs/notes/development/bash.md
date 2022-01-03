# Bash | Development notes

## Know issues

### Update bash script in a running one

Issue:
The bash script will interpret each line when it's executed, if you update a running bash script it will use new bash file, if there are references in the new bash file on the line that's in execution, it could be a disaster.

See the example:

- [77TB of Research Data Lost Because of HPE Software Update](https://www.tomshardware.com/news/77tb-of-critical-research-data-lost-because-of-hpe-software-update)

Options:
1. Use block delimiter
2. Rename the script

Option 1: Using block delimiter
> [Reference](https://stackoverflow.com/questions/2336977/can-a-shell-script-indicate-that-its-lines-be-loaded-into-memory-initially/2337400#2337400)
``` bash
#!/bin/sh
{
    # Your stuff goes here
    exit
}
```

Option 2: Rename the script
> [Reference](https://stackoverflow.com/questions/2336977/can-a-shell-script-indicate-that-its-lines-be-loaded-into-memory-initially/2337400#2337400)
``` bash
mv script script-old
cp script-old script
rm script-old
```
