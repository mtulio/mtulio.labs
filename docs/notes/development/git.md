# GIT

Some useful commands.

## TAGs

### Create tags

* List current tags

`git tag`

* Create a new one

`git tag 0.1 -m "Add the 0.1 tag to put it in the first PyPi pkg"`

* Push new tag

`git push --tags origin`

### Update tags

* Delete the tag on any remote before you push

`git push origin :refs/tags/<tagname>`

* Replace the tag to reference the most recent commit

`git tag -fa <tagname>`

* Push the tag to the remote origin

`git push origin master --tags`

### Backking up

#### Moving directory to new repo

Refs:
- https://help.github.com/en/github/using-git/splitting-a-subfolder-out-into-a-new-repository


