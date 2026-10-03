# mtulio.dev Apps

Apps page hosts static html apps hosted by mkdocs.

Access those using the url https://mtulio.dev/apps/<app_name>.

Available apps:

- [htmlpreview](https://mtulio.dev/apps/htmlpreview): Powered by [htmlpreview.github.io](https://github.com/htmlpreview/htmlpreview.github.com)


## Apps Setup


### htmlpreview

Steps to update:
- clone/copy the repo content into the directory htmlpreview
- remove unused data to prevent mkdocs rendering: 
```sh
rm docs/apps/htmlpreview/readme.md
```
- update htmlpreview.js to match the relative path
```sh
sed -i 's/\"\/htmlpreview.js/"\.\/htmlpreview.js/' docs/apps/htmlpreview/index.html
```
