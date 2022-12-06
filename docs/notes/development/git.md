# GIT | Development notes

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


## Ramdom Examples

### Squash current branch (without preserving old commits)

```
git checkout feature/support-component
git reset upstream/master
git add vendor/ go.sum go.mod 
git commit -m 'Provider: add Vendor code required to introduce'
git status
git add .gitignore Dockerfile Dockerfile.okd pkg/ pkg/ manifests/ 
git status
git commit -m 'Provider: add components'
git push -f
```

### Squash current branch (without preserving old commits)

- Example squash the oldest 3 commits
```
git rebase main
git rebase -i HEAD~3
# edit the lines from `pick` to `squash`
# add a commit message
git push -f
```

References:
- https://www.git-tower.com/learn/git/faq/git-squash
