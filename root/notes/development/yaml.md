# YAML


Table for scapes in the keys:

```text
                      >     |            "     '     >-     >+     |-     |+
-------------------------|------|-----|-----|-----|------|------|------|------  
Trailing spaces   | Kept | Kept |     |     |     | Kept | Kept | Kept | Kept
Single newline => | _    | \n   | _   | _   | _   | _    |  _   | \n   | \n
Double newline => | \n   | \n\n | \n  | \n  | \n  | \n   |  \n  | \n\n | \n\n
Final newline  => | \n   | \n   |     |     |     |      |  \n  |      | \n
Final dbl nl's => |      |      |     |     |     |      | Kept |      | Kept  
In-line newlines  | No   | No   | No  | \n  | No  | No   | No   | No   | No
Spaceless newlines| No   | No   | No  | \   | No  | No   | No   | No   | No 
Single quote      | '    | '    | '   | '   | ''  | '    | '    | '    | '
Double quote      | "    | "    | "   | \"  | "   | "    | "    | "    | "
Backslash         | \    | \    | \   | \\  | \   | \    | \    | \    | \
" #", ": "        | Ok   | Ok   | No  | Ok  | Ok  | Ok   | Ok   | Ok   | Ok
Can start on same | No   | No   | Yes | Yes | Yes | No   | No   | No   | No
line as key       |
```

***source [here](https://stackoverflow.com/questions/3790454/in-yaml-how-do-i-break-a-string-over-multiple-lines/21699210) 
