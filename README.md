# Functions and Scripts for Interactive Bash Sessions
###### [Kevin P. Barry][1], Last Updated 12 July 2016

This project includes several shell functions and scripts that I've found
extremely useful while doing a lot of work from a terminal. For the most part,
they're meant to cut down on repetition when dealing with command history and
renaming files.

## Bash Functions from .bash_functions
To use, copy [`bash_functions`](bash_functions "Bash Functions") to `~` and
add this line to `~/.bashrc`:

```bash
[ -r ~/bash_functions ] && . ~/bash_functions
```

The next time you start an interactive bash session, the functions below should
be available for use.

### History Functions

These functions filter, alter, and/or reexecute commands from the command
history. **Note that since history lines are enumerated for the purposes of
matching and filtering, `^` won't match the beginning of a command. Use
`${HPREFIX}` where you would otherwise use `^` in a pattern to indicate the
beginning of a line, e.g., `"(${HPREFIX}| )echo "` instead of `'(^| )echo '`.**

#### Filter Command History: `hgrep` *`[regex]`*
Filter shell command history using an extended regular expression. Sorts by
recency.

```bash
bash$ echo 123
123
bash$ echo hello
hello
bash$ hgrep echo
echo hello
echo 123
```

#### Redirect *Quoted* Command from History: `hecho` *`[regex]`* *`(count)`*
Interactively select a command from history, then optionally provide redirection
of the *text* of the command. The optional `(count)` argument indicates the max
number of choices to show.

```bash
# (setup)
bash$ echo 123 1>&2
123
bash$ echo hello
hello

# WITH REDIRECTION
bash$ hecho echo
1) echo hello
2) echo 123 1>&2
#? 2
edit: echo 123 1>&2
redirect: >> ~/my-new-script.sh
bash$ cat ~/my-new-script.sh
echo 123 1>&2

# WITHOUT REDIRECTION
bash$ x=$(hecho echo)
1) echo hello
2) echo 123 1>&2
#? 2
edit: echo 123 1>&2
bash$ echo "$x"
echo 123 1>&2
```

#### Execute Command from History: `hsel` *`[regex]`* *`(count)`*
Interactively select a command from history, then execute the selected command.
The optional `(count)` argument indicates the max number of choices to show.

```bash
bash$ ls -lht ~/Downloads
total 0

...

bash$ hsel Downloads
1) ls -lht ~/Downloads
#? 1
edit: ls -lht ~/Downloads
total 0
```

#### Revise or Remove Command from History: `oops` *`(regex)`*
With no arguments, the last command that was run will be removed, or edited,
executed, and replaced in history. With a regex argument, commands in history
that match will be removed from the history. Confirmation will happen in the
latter case before removal.

```bash
# EDIT, EXECUTE AND REPLACE
bash$ echo123
echo123: command not found
bash$ oops
edit: echo 123
123
#('echo 123' replaces 'echo123' in history)

# REMOVE
bash$ echo123
echo123: command not found
bash$ oops
edit: echo123^C
#('echo123' is now no longer in history)

# REMOVE ALL MATCHES
bash$ echo123
echo123: command not found
bash$ echo456
echo456: command not found
bash$ oops "${HPREFIX}echo[^ ]"
echo123
echo456
Press [Enter] to proceed...
Deleting...
```

#### Sharing History

The [`history-collector.py`](history-collector.py "History Collector Script")
script manages history between multiple concurrent sessions. This sharing only
applies to the history functions in this project. To enable history sharing,
call `use_history_collector (script)`, where `(script)` is an optional location
of [`history-collector.py`](history-collector.py "History Collector Script"),
defaulting to `$HOME/bin/history-collector.py`.

Notes:
- [`history-collector.py`](history-collector.py "History Collector Script")
  isn't meant to be used directly!
- The `oops` function assumes that no history updates take place while you are
  examining the line(s) to delete.
- The history collector daemon is single-threaded, but that shouldn't matter
  unless a bug prevents it from completing a request.
- History data is saved in `$HOME/.hc_history`, and can be saved/restored for
  the current session with `save_history` and `restore_history`, respectively.
- Unfortunately, updates to the shared history are delayed by one command, due
  to the limited configurability of `bash`.
- When enabled, history collection will periodically call `history -a ...`,
  which will "steal" history from the current session. This doesn't affect the
  session's history (accessed via the up key and `history`); however, it might
  prevent it from getting saved to `.bash_history`.

### Directory Functions

#### Traverse Downward Until Stuck: `follow` *`(resolvers...)`*
From the current directory, iteratively `cd` downward until nothing else makes
sense. If at any point the current directory only contains one other (visible)
directory and no visible files, `cd` to that directory; otherwise, check the
next `(resolvers...)` argument for and explicit directory to `cd` to. The
previous directory will be the directory where the `follow` call was made.

```bash
bash:~$ install -d this/is/too/much
bash:~$ install -d this/is/also/much
bash:~$ follow this && pwd
/home/me/this/is
bash:~/this/is$ follow ~ this also && pwd
/home/me/this/is/also/much
```

#### Switch To the *n*<sup>th</sup> Directory: `ncd` *`[n]`*, or `ncd` *`[path]`* *`[n...]`*
`cd` to the *n*<sup>th</sup> *visible* directory, optionally starting from
*`[path]`*. If *n* is negative, `cd` to the *n*<sup>th</sup>-to-last directory.
The previous directory will be the directory where the `ncd` call was made. If a
starting path is used, you may specify any number of *n*s that are used in
order.

```bash
bash:~$ mkdir 1 2 3
bash:~$ ncd 1 && pwd
/home/me/1
bash:~/1$ ncd ~ -1 && pwd
/home/me/3
```

You can actually use a regular expression instead of any given *n* if you
surround it with `/` (`sed` line-matching syntax), e.g.,

```bash
bash:~$ ncd /[Dd]own/ && pwd
/home/me/Downloads
```

#### Get Path of the *n*<sup>th</sup> Directory: `ndir` *`[n]`*, or `ndir` *`[path]`* *`[n...]`*
Same as `ncd`, but echo the destination path rather than performing a `cd`.

#### Switch Directories without Updating Previous: `icd` *`[path]`*
`cd` to *`[path]`* without updating the previous directory (`~-`). (The `i` is
meant to indicate "incremental".) This is helpful if you want to `cd` to a
directory with a long path a few components at a time, or if you want to `cd`
somewhere without overwriting `~-`.

```bash
bash:/$ icd /home 
bash:/home$ icd me
bash:~$ cd ~- && pwd
/
```

#### Traverse Upward *n* Times: `ucd` *`[n]`*
`cd ..` *n* times. The previous directory will be the directory where the `ucd`
call was made. If *n* is negative, this will traverse upward until the current
directory is *-n* from `/`.

```bash
bash:/there/are/too/many/paths$ ucd 3 && pwd
/there/are
```

```bash
bash:/there/are/too/many/paths$ ucd -3 && pwd
/there/are/too
```

#### Switch Directories to a Parallel Branch: `scd` *`[old]`* *`[new]`*
`cd` to `pwd` after making a text substitution in that path. This is useful if
you have the same directory structure in two different places, e.g., different
branches of the same repository.

```bash
bash:/home/me/some/path$ scd me you && pwd
/home/you/some/path
```

#### Traverse Upward to Specific Directory: `cdto` *`[basename]`*
`cd` upward until the `basename` of `pwd` matches the first argument.

```bash
bash:/home/me/some/path$ cdto me && pwd
/home/me
```

#### Compute a Relative Path Change: `relpath` *`[from path]`* *`[to path]`*
Determine the most-efficient relative `cd` that can be made to get between two
paths.
  * The paths don't need to exist!
  * The fully-dereferenced `pwd` will be prepended to all relative paths before
  processing.
  * Path components of the arguments won't be dereferenced, which might make
  results inaccurate if upward traversal is required.

```bash
bash:~$ relpath . /root
../../root
bash:~$ relpath x/y/z /1/2/3
../../../../../1/2/3
```

### Filtering Functions

#### Filter Input Except for First Line: `skiphead` *`[command...]`*
Holds the first line aside, then executes `[command...]` on the rest of the
input. Output contains the first line where it was, followed by filtered output.

```bash
bash$ ps | skiphead sort -g
  PID TTY          TIME CMD
12995 pts/0    00:00:01 bash
23109 pts/0    00:00:00 ps
23110 pts/0    00:00:00 bash
```

#### Mute Standard Error for a Command: `mute` *`[command...]`*
Executes the command with standard error redirected into /dev/null.

```bash
bash$ ls fake
ls: cannot access fake: No such file or directory
bash$ mute ls fake
```

## Shell Scripts

To use, copy the scripts from `bin` to somewhere in your `$PATH`.

#### Rename Files With a Pattern: [`useful-rename.sh`](useful-rename.sh "Rename Script") *`[from regex]`* *`[to regex]`* *`(files...)`*
Rename `(files...)` by transforming filenames *(with paths)* using `sed`-like
replacement. **The script will refuse to rename any files if there are any
collisions among the source and destination files.** Prefix with `RENAME_ARGS=`
to supply additional arguments to the rename command. Missing destination paths
*will not* be created.

```bash
bash$ touch {a,b,c}.txt
bash$ useful-rename.sh '\.' '1.' *.txt
mv -fv a.txt a1.txt
'a.txt' -> 'a1.txt'
mv -fv b.txt b1.txt
'b.txt' -> 'b1.txt'
mv -fv c.txt c1.txt
'c.txt' -> 'c1.txt'
```

#### Copy Files With a Pattern: [`useful-copy.sh`](useful-copy.sh "Copy Script") ...
Same as `useful-rename.sh`, but creates copies instead. (You can just create a
symlink to `useful-rename.sh` named `useful-copy.sh`.)

#### Symlink Files With a Pattern: [`useful-link.sh`](useful-link.sh "Link Script") ...
Same as `useful-rename.sh`, but creates symlinks instead. (You can just create a
symlink to `useful-rename.sh` named `useful-link.sh`.)

#### Custom Rename Command With a Pattern: `RENAME_CMD='...'` `useful-rename.sh` ...
Replace the rename command used by `useful-rename.sh`. This is useful if you
want the same pattern transformation and error checking with some other command.

```bash
bash$ mkdir temp
bash$ touch temp/{a,b,c}.txt
bash$ RENAME_CMD='install -D -m0644' useful-rename.sh 'temp/(.+)$' 'temp2/\1~' temp/*.txt
install -D -m0644 temp/a.txt temp2/a.txt~
install -D -m0644 temp/b.txt temp2/b.txt~
install -D -m0644 temp/c.txt temp2/c.txt~
```

  [1]: mailto:kevinbarry@google.com
