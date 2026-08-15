# SVN Keep MTime Architecture

## 1. Overview

SVN Keep MTime is a client-side SVN wrapper.

Its purpose is to preserve filesystem modification time (`mtime`)
through SVN operations by storing the timestamp as an SVN property:

``` text
file:mtime
```

The SVN server and repository format are not modified. SVN Keep MTime
operates between the user and the original SVN client.

``` text
                         User
                           |
                           v
                          svn
                           |
                           v
                       svn_kmt
                     /         \
                    /           \
             KMT processing   svn_kmt_org
                                  |
                                  v
                           SVN repository
```

The normal SVN client remains responsible for all actual SVN operations.

------------------------------------------------------------------------

## 2. Installed Components

### 2.1 `svn`

After installation, `svn` is a symbolic link:

``` text
svn -> svn_kmt
```

The user continues to invoke SVN normally:

``` sh
svn update
svn commit
svn checkout
```

### 2.2 `svn_kmt`

`svn_kmt` is the installed SVN wrapper.

It:

-   detects KMT-specific commands;
-   intercepts selected SVN operations;
-   maintains `file:mtime`;
-   synchronizes local timestamps;
-   forwards normal SVN work to the original SVN executable.

### 2.3 `svn_kmt_org`

`svn_kmt_org` is the original SVN executable saved by the installer.

The wrapper invokes it for the underlying SVN operation.

The resulting installation is:

``` text
<SVN bin directory>/
    svn -> svn_kmt
    svn_kmt
    svn_kmt_org
```

------------------------------------------------------------------------

## 3. Source and Installation Model

The distribution source is:

``` text
shell/svn_kmt.sh
```

The file name is part of the installation contract.

Installation is performed by:

``` sh
./svn_kmt.sh kmt-install
```

The installer normally copies the source file to the installed
`svn_kmt`.

Development/test link mode is available:

``` sh
./svn_kmt.sh kmt-install --link
```

In link mode, `svn_kmt` links back to the source script.

The installer then:

1.  Finds the current SVN executable.
2.  Installs `svn_kmt`.
3.  Moves the original `svn` to `svn_kmt_org`.
4.  Creates `svn -> svn_kmt`.

Rollback logic is used for several installation failures so that a
partially installed wrapper does not intentionally replace the original
SVN client.

------------------------------------------------------------------------

## 4. Installation and Upgrade

### 4.1 Install

``` text
svn_kmt.sh
    |
    v
kmt-install
    |
    +--> install svn_kmt
    |
    +--> move svn -> svn_kmt_org
    |
    +--> create svn -> svn_kmt
```

### 4.2 Upgrade

Upgrade is intentionally started from the distribution script:

``` sh
./svn_kmt.sh kmt-upgrade
```

If an installation already exists:

``` text
svn_kmt.sh
    |
    v
kmt-upgrade
    |
    v
svn kmt-uninstall
    |
    +--> restore original svn
    |
    +--> remove old svn_kmt
    |
    v
kmt-install
    |
    +--> install new svn_kmt
    |
    +--> create svn -> svn_kmt
```

If no installation exists, upgrade falls back to installation.

The source filename check prevents the install/upgrade operations from
being started through the installed wrapper.

------------------------------------------------------------------------

## 5. Uninstall

The supported uninstall entry point is:

``` sh
svn kmt-uninstall
```

The installed wrapper verifies the installation state and then:

``` text
svn -> svn_kmt
       |
       v
remove svn link
       |
       v
svn_kmt_org -> svn
       |
       v
remove svn_kmt
```

The original SVN executable is restored before the wrapper is removed.

------------------------------------------------------------------------

## 6. SVN Command Dispatch

The dispatcher separates normal SVN operations from KMT operations.

### Intercepted SVN operations

The current implementation adds mtime processing to:

``` text
commit / ci
update / up
checkout / co
revert
```

### KMT operations

``` text
kmt
kmt-ui
kmt-main

kmt-complete
kmt-synchronize
kmt-resolve

kmt-version
kmt-install
kmt-uninstall
kmt-upgrade
```

Other commands are forwarded to the original SVN client.

------------------------------------------------------------------------

## 7. Commit Processing

The commit path is:

``` text
svn commit
     |
     v
svn_kmt
     |
     v
collect files reported by svn status
     |
     v
read local filesystem mtime
     |
     v
validate mtime
     |
     +---- invalid/conflicting ----> stop
     |
     v
set file:mtime property
     |
     v
svn_kmt_org commit
     |
     v
repository
```

For added or modified files, the wrapper attempts to save the local
filesystem timestamp before calling the original SVN commit.

### 7.1 Safety checks

`save_a_file_mtime()` performs several important checks.

#### Future timestamp

A timestamp later than the current system time is rejected:

``` text
local mtime > now
```

The file is not given future `file:mtime` metadata.

#### Existing identical metadata

If:

``` text
local mtime == file:mtime
```

no property change is required.

#### Modified-file conflict with existing metadata

If a modified file has an existing property and:

``` text
local mtime < file:mtime
```

the operation is rejected.

#### Modified-file conflict with version timestamp

If the file is locally modified and:

``` text
local mtime < last versioned commit timestamp
```

the operation is rejected.

These checks prevent a local timestamp from moving repository metadata
backwards unexpectedly.

------------------------------------------------------------------------

## 8. Update / Checkout / Revert Processing

The wrapper processes selected SVN output after the original SVN command
has run.

For a file with valid `file:mtime` metadata:

``` text
svn update / checkout / revert
             |
             v
       svn_kmt_org
             |
             v
        changed file
             |
             v
      read file:mtime
             |
             v
       set filesystem mtime
```

The timestamp is applied using platform-specific filesystem commands.

### 8.1 Local conflict detection

During an update, if the repository metadata timestamp is newer than the
local filesystem timestamp in the relevant update state, the wrapper
reports a conflicting mtime instead of silently replacing the local
timestamp.

This protects a potentially meaningful local timestamp from being
overwritten blindly.

------------------------------------------------------------------------

## 9. File mtime Metadata

The metadata property is:

``` text
file:mtime
```

The property value is a Unix timestamp represented as decimal digits.

Conceptually:

``` text
path/to/file
    |
    +-- file:mtime = <unix timestamp>
```

The repository property is the persistent representation of the
filesystem timestamp.

The extension does not put the timestamp into the file contents.

------------------------------------------------------------------------

## 10. KMT Manager

The KMT manager is implemented by the `kmt_command()` and `kmt_ui()`
functions.

The preferred entry point is:

``` sh
svn kmt
```

Aliases:

``` sh
svn kmt-ui
svn kmt-main
```

The interactive menu contains:

``` text
1  Scan the directories
2  List the completed files
3  List the files need to complete metadata
4  List the files need to synchronize mtime
5  List files with mtime conflicts
6  List working-copy files without file:mtime metadata
7  Complete file:mtime metadata
8  Synchronize local file mtime
9  Resolve mtime conflicts
```

The manager can repeatedly perform operations until the user exits.

------------------------------------------------------------------------

## 11. KMT Operation Model

The internal KMT operations are:

``` text
scan
show_completed
show_completable
show_synchronizable
show_conflict
show_unsynchronizable
complete
synchronize
resolve
```

The direct command mapping is:

``` text
svn kmt-complete     -> complete
svn kmt-synchronize  -> synchronize
svn kmt-sync         -> synchronize
svn kmt-resolve    -> resolve
```

The `svn kmt` command exposes the same operations through the
interactive menu.

------------------------------------------------------------------------

## 12. Working Copy Safety

Before KMT modifying operations:

``` text
complete
synchronize
resolve
```

the wrapper verifies that the selected working copy is up to date.

The check compares:

``` text
local working-copy revision
repository HEAD revision
```

It also requires the SVN schedule to be `normal`.

For modifying KMT operations, the working copy must not contain
uncommitted added/modified/conflicted files.

The purpose is to keep metadata processing separate from ordinary user
changes.

------------------------------------------------------------------------

## 13. Scan and Classification

The scanner gathers four values for each versioned path:

``` text
path
local filesystem mtime
file:mtime property
versioned commit timestamp
```

Conceptually:

``` text
                   +----------------------+
                   | versioned path       |
                   +----------+-----------+
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
        local mtime       file:mtime       version time
             |                |                |
             +----------------+----------------+
                              |
                              v
                       classification
```

The current KMT classification model is based on five states:

``` text
Completed
Completable
Synchronizable
Conflict
Unsynchronizable
```

### 13.1 Existing metadata

When `file:mtime` exists:

-   equal local/property timestamps are **completed**;
-   a local timestamp newer than the property is **synchronizable**;
-   a local timestamp older than the property is a **conflict**;
-   directories with metadata are treated as completed.

A synchronizable file means that the repository already contains
`file:mtime`, so the local filesystem mtime can safely be synchronized
from the repository metadata, subject to the working-copy checks.

### 13.2 Missing metadata

When `file:mtime` is absent, the scanner compares:

``` text
local filesystem mtime
```

with:

``` text
latest versioned commit timestamp
```

If:

``` text
local mtime < latest versioned commit timestamp
```

the file is **completable**.

This classification identifies a working copy that may still contain the
original file modification time. KMT allows the local timestamp to be
used to complete the missing repository metadata, subject to the normal
mtime safety checks.

If:

``` text
local mtime >= latest versioned commit timestamp
```

the file is **unsynchronizable** in the current working copy.

The repository does not yet contain `file:mtime`, and this working copy
is not eligible to complete it. The file should be completed from
another working copy that still contains the original file modification
time.

Once another working copy successfully completes and commits the
property, the file becomes synchronizable on other working copies.

The important distinction is:

``` text
No file:mtime
    |
    +--> local mtime < version timestamp
    |        |
    |        v
    |   Completable
    |
    +--> local mtime >= version timestamp
             |
             v
       Unsynchronizable
```

This allows missing metadata for a large repository to be distributed
across many hosts. Each host can independently scan its working copy,
and KMT determines eligibility per file rather than requiring a user to
manually assign files to a particular host.

## 14. Completing Missing Metadata

The `complete` operation uses the local filesystem timestamp as the
source for a missing `file:mtime` property:

``` text
local mtime
      |
      v
file:mtime property
      |
      v
SVN commit
```

The operation is not a general-purpose "copy every local timestamp into
SVN" operation.

Before processing files, KMT requires an up-to-date working copy and no
ordinary uncommitted changes.

For each missing `file:mtime`, the scanner must already have classified
the file as **completable**. The operation then applies the same mtime
safety rules used by normal commit processing, including:

-   future local timestamps are rejected;
-   timestamps that violate the versioned commit-time ordering rule are
    rejected;
-   unsafe or ambiguous cases are not silently written.

After properties are successfully set, KMT commits the metadata with an
automatically generated commit message and updates the working copy.

A successful completion changes the repository state for the file from:

``` text
file:mtime not completed
```

to:

``` text
file:mtime completed
```

Other working copies can then classify the file as **synchronizable**.

### Existing repository initialization workflow

For an existing repository, completion and synchronization work
together:

``` text
Working copy A
    |
    | local mtime is eligible
    v
Completable
    |
    | complete
    v
file:mtime committed to repository
    |
    +------------------+
    |                  |
    v                  v
Working copy B     Working copy C
    |                  |
Synchronizable     Synchronizable
    |                  |
    v                  v
Synchronize        Synchronize
```

There is no requirement for one user or one host to complete the entire
repository. Different files may be completable on different working
copies.

The desired end state is:

``` text
Completed:          all versioned files
Completable:        0
Synchronizable:     0
Conflicts:          0
Unsynchronizable:   0
```

## 15. Synchronize Local mtime

The `synchronize` operation takes the timestamp from the repository:

``` text
file:mtime
     |
     v
filesystem mtime
```

Only files classified as **synchronizable** are changed.

No SVN commit is required because synchronization changes the local
filesystem timestamp rather than repository metadata.

The operation requires the same working-copy safety checks as other KMT
modifying operations.

Once the existing repository has been initialized, normal daily SVN
operations automatically maintain these timestamps. Users normally do
not need to run `kmt-complete` or `kmt-synchronize` manually after
ordinary `svn commit`, `svn update`, `svn checkout`, or `svn revert`
operations.

## 16. Resolve Mtime Conflicts

The `resolve` operation is for mtime conflicts.

Conceptually:

``` text
repository file:mtime
           |
           | conflict
           v
local filesystem mtime
           |
           v
       safety checks
           |
      +----+----+
      |         |
    valid     invalid
      |         |
      v         v
replace      remain
metadata     unresolved
      |
      v
  SVN commit
```

The local timestamp is used as the **candidate** replacement value.

Resolve does not force the local mtime into the repository
unconditionally. The candidate timestamp must still pass the normal
future-time, ordering, and other mtime safety checks.

If the candidate local timestamp is not valid, the file remains
unresolved and the user must decide how to handle it.

This design intentionally leaves room for future per-file conflict
resolution, similar in spirit to ordinary SVN content-conflict handling.

## 17. Scanning Backends

Three scanner implementations are available:

``` text
python
join
posix
```

### 17.1 Automatic selection

If no backend is specified:

``` text
Python available?
    |
   yes ---> python
    |
   no
    |
join + awk available?
    |
   yes ---> join
    |
   no
    |
   posix
```

### 17.2 Python backend

The Python backend collects:

-   recursive SVN paths;
-   `file:mtime` properties;
-   recursive SVN XML information;
-   local filesystem mtimes.

It supports Python 2 and Python 3 syntax in the embedded scanner
implementation.

### 17.3 Join backend

The join backend uses standard command-line tools to build sorted
intermediate datasets and joins:

``` text
filesystem paths + local mtime
        +
file:mtime properties
        +
SVN version timestamps
```

The backend uses tools such as:

``` text
svn
stat
awk
sort
join
xargs
```

### 17.4 POSIX backend

The POSIX backend uses the simpler per-file processing path:

``` text
svn ls -R
    |
    v
get local mtime
    |
    v
get file:mtime
    |
    v
get versioned timestamp
    |
    v
classify file
```

It is the fallback scanner when the optimized backends are unavailable.

### 17.5 Explicit selection

The backend can be selected with:

``` sh
--scan-backend=python
--scan-backend=join
--scan-backend=posix
--scan-backend=auto
```

For example:

``` sh
svn kmt --scan-backend=join
```

or:

``` sh
svn kmt-synchronize --scan-backend=posix
```

------------------------------------------------------------------------

## 18. Platform Handling

The current implementation supports:

``` text
Linux
macOS
```

Platform-specific operations include reading filesystem mtime:

``` text
Linux:  stat -c %Y
macOS:  stat -f %m
```

and setting filesystem mtime:

``` text
Linux:  touch -m -d "@<timestamp>"
macOS:  touch -m -t ...
```

The wrapper detects the platform at startup and rejects unsupported
platforms.

------------------------------------------------------------------------

## 19. Time Handling

The property stores Unix timestamps.

The wrapper also detects the local timezone offset and uses it when
displaying timestamps.

Repository commit timestamps are obtained from SVN information and
converted to Unix timestamps before comparison.

The comparisons themselves are numeric timestamp comparisons.

------------------------------------------------------------------------

## 20. Debugging

The wrapper has an internal debug logger.

Debug mode can be enabled by placing:

``` text
--kmt-debug
```

before the actual command arguments.

Example:

``` sh
svn --kmt-debug update
```

Debug information is written to standard error.

The logger records command flow and timing information useful for
diagnosing scanner and wrapper behavior.

------------------------------------------------------------------------

## 21. Design Principles

### 21.1 Client-side only

No SVN server extension is required.

### 21.2 Metadata only

The file contents are not modified by KMT.

The persistent mtime information is stored in:

``` text
file:mtime
```

### 21.3 Preserve normal SVN behavior

Commands not requiring KMT processing are forwarded directly to the
original SVN executable.

### 21.4 Conservative timestamp handling

The implementation does not blindly overwrite timestamps when the local
and repository values disagree.

### 21.5 Working-copy isolation

KMT metadata management requires an up-to-date working copy and, for
modifying KMT operations, a clean working copy.

### 21.6 Simple deployment

The complete implementation is contained in:

``` text
shell/svn_kmt.sh
```

The same script provides the wrapper, KMT manager, installer, and
upgrade logic.

------------------------------------------------------------------------

## 22. Current Command Surface

### User SVN commands

``` text
svn checkout
svn update
svn add
svn commit
svn status
svn revert
```

### KMT commands

``` text
svn kmt
svn kmt-ui
svn kmt-main

svn kmt-complete
svn kmt-synchronize
svn kmt-resolve

svn kmt-version
svn kmt-uninstall
```

### Distribution-script commands

``` text
./svn_kmt.sh kmt-install
./svn_kmt.sh kmt-install --link
./svn_kmt.sh kmt-upgrade
```

The installation/upgrade script must remain named:

``` text
svn_kmt.sh
```

------------------------------------------------------------------------

## 23. Error and Safety Philosophy

The wrapper favors stopping over silently making an uncertain timestamp
decision.

Examples:

``` text
future timestamp
    -> reject

mtime older than trusted repository time
    -> reject when safety rule applies

SVN conflict
    -> report / stop

working copy not up to date
    -> reject KMT modifying operation

uncommitted changes
    -> reject KMT modifying operation
```

This is particularly important because an incorrect `file:mtime` value
becomes repository metadata and may later be propagated to other working
copies.
