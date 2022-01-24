# BASH | Notes

## PS1

```
parse_git_branch() {
     git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1="\u@\h \[\033[32m\]\w\[\033[33m\]\$(parse_git_branch)\[\033[00m\] $ "
```

References:
- [https://coderwall.com/p/fasnya/add-git-branch-name-to-bash-prompt](https://coderwall.com/p/fasnya/add-git-branch-name-to-bash-prompt)
