# WSL

## Troubleshooting

### network issues

- Reset network issues

[Reference](https://github.com/microsoft/WSL/issues/5336#issuecomment-653881695)

~~~
=============================================================================
FIX WSL2 NETWORKING IN WINDOWS 10
=============================================================================
cmd as admin:
wsl --shutdown
netsh winsock reset
netsh int ip reset all
netsh winhttp reset proxy
ipconfig /flushdns

Windows Search > Network Reset

Restart Windows
-----------------------------------------------------------------------------
~~~