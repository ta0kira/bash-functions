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

Command history can be searched and shared across terminals. There are a few
requirements to enable this functionality.

1. Make sure that the [`sqlite3`](https://www.sqlite.org/index.html) CLI is
   installed and is in your `$PATH`.
1. *(Optional)* Install `pcre` for `sqlite3`. On Linux, this might be in a
   package named `sqlite3-pcre`. If the installed path *isn't*
   `/usr/lib/sqlite3/pcre.so` then `export` `SQLITE3_REGEX_LIB` with the
   absolute path in `.bashrc`. (This will enable regexes in history search. The
   default otherwise will be glob searches.)
1. *(Optional)* Put `history-collector.sh` in `$HOME/bin`, or create a symlink.
1. Call `use_history_collector` in `.bashrc`. If `history-collector.sh` *isn't*
   in `$HOME/bin` then pass the absolute path to `use_history_collector`.

 in `.bashrc` after the applicable `export`s
   above.

Non-shared versions of the functions below will be available without the steps
above, but it might be buggy. (If you use the default (non-shared) history
functions, use `$HPREFIX` instead of `^` to indicate the beginning of a line in
search regexes.)

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
bash$ oops "echo[^ ]"
echo123
echo456
Press [Enter] to proceed...
Deleting...
```

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

  [1]: mailto:kevinbarry@google.com
