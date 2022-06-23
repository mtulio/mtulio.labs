# Github actions


## act tool

- Run in podman

> Ref https://github.com/nektos/act/issues/303#issuecomment-962403508

```bash
systemctl start podman
systemctl enable --now --user podman.socket
sudo usermod -G docker $(whoami)

export PODMAN_SOCK="/run/user/$(id -u)/podman/podman.sock"
export DOCKER_HOST=unix://${PODMAN_SOCK}
act --bind \
    --container-daemon-socket ${PODMAN_SOCK} \
    -W .github/workflows/ci.yaml
```
