# SVN Keep MTime

SVN Keep MTime (`svn_kmt`) is an SVN client wrapper that preserves
filesystem modification time (`mtime`) for versioned files.

SVN itself does not preserve the original filesystem `mtime` as
repository metadata. SVN Keep MTime stores the timestamp in the SVN
property:

``` text
file:mtime
```

The extension works entirely on the SVN client side. It does not require
changes to the SVN server or repository format.

## Quick Start

Download and extract the release archive, then install SVN Keep MTime:

The latest release is available on GitHub Releases.
https://github.com/beaucity/svn-keep-mtime/releases

``` sh
cd svn-keep-mtime/shell
chmod +x svn_kmt.sh
./svn_kmt.sh kmt-install
```

After installation, use SVN normally:

``` sh
svn checkout <URL>
svn update
svn commit
```

Installing SVN Keep MTime does not automatically change or synchronize
the modification times of files in existing working copies.

For an existing working copy, run the following command to scan and
manage file:mtime metadata:

``` sh
svn kmt
```

## Features

-   Automatically records local file `mtime` in `file:mtime` when files
    are committed.
-   Automatically synchronizes local filesystem `mtime` from
    `file:mtime` after `update`, `checkout`, and `revert` operations.
-   Detects conflicting modification times instead of blindly
    overwriting them.
-   Rejects attempts to commit a future file timestamp.
-   Provides a `svn kmt` interactive manager for inspection,
    existing-repository initialization, mtime synchronization, and
    conflict resolution.
-   Supports repositories that were created before SVN Keep MTime was
    installed.
-   Provides multiple scan backends for KMT management operations.
-   Keeps the original SVN executable as `svn_kmt_org`.

## How It Works

The basic data flow is:

``` text
Local file
   |
   | filesystem mtime
   v
file:mtime SVN property
   |
   v
SVN repository
```

When a file is committed:

``` text
local file mtime
      |
      v
file:mtime property
      |
      v
svn_kmt_org
      |
      v
SVN repository
```

When a file is checked out, updated, or reverted:

``` text
SVN repository
      |
      v
file:mtime property
      |
      v
svn_kmt
      |
      v
local file mtime restored
```

The extension does not replace normal SVN behavior. The original SVN
client still performs the actual SVN operation.

## Installation

The distribution contains:

``` text
shell/svn_kmt.sh
```

The installation script **must keep the filename `svn_kmt.sh`**.

Install with:

``` sh
./svn_kmt.sh kmt-install
```

The script can also be run as:

``` sh
./svn_kmt.sh install
```

After installation, the SVN executable directory contains:

``` text
svn -> svn_kmt
svn_kmt
svn_kmt_org
```

`svn` becomes a symbolic link to `svn_kmt`, while the original SVN
executable is moved to `svn_kmt_org`.

The installed `svn_kmt` is the client wrapper. It calls `svn_kmt_org`
for the actual SVN operation and adds mtime processing where required.

### Link installation mode

By default, the installer copies `svn_kmt.sh` to the installed
`svn_kmt`.

For development or local testing, link mode is also available:

``` sh
./svn_kmt.sh kmt-install --link
```

In link mode, the installed `svn_kmt` points to the supplied
`svn_kmt.sh`.

## Upgrade

Upgrade must be started from the distribution script:

``` sh
./svn_kmt.sh kmt-upgrade
```

The installer also accepts:

``` sh
./svn_kmt.sh upgrade
```

If an older SVN Keep MTime installation is present, the upgrade process:

1.  Uninstalls the current wrapper.
2.  Restores the original SVN executable.
3.  Installs the new `svn_kmt`.
4.  Reconnects `svn` to the new wrapper.

If SVN Keep MTime is not installed, `kmt-upgrade` installs it.

The `svn_kmt.sh` filename check is intentional. Do not rename the
distribution installation/upgrade script.

## Uninstall

Uninstall an installed copy with:

``` sh
svn kmt-uninstall
```

The uninstall command is intentionally executed through the installed
SVN wrapper.

The wrapper:

1.  Removes the `svn -> svn_kmt` link.
2.  Restores `svn_kmt_org` to `svn`.
3.  Removes the installed `svn_kmt`.

After successful uninstall, the normal SVN executable is restored.

Do **not** use the distribution script as the uninstall entry point.

## Normal SVN Usage

After installation, normal SVN commands remain unchanged:

``` sh
svn checkout URL
svn update
svn add file
svn commit
svn status
svn revert file
```

SVN Keep MTime currently integrates mtime handling with:

-   `commit` / `ci`
-   `update` / `up`
-   `checkout` / `co`
-   `revert`

Other SVN commands are forwarded to the original SVN client without
additional KMT processing.

### Commit behavior

Before a commit, SVN Keep MTime examines files reported by `svn status`
as added or modified and tries to maintain their `file:mtime` property.

Important safety checks include:

-   A future local `mtime` is rejected.
-   An existing identical `file:mtime` is left unchanged.
-   A modified file cannot replace existing metadata with an earlier
    timestamp.
-   A modified file cannot use an `mtime` earlier than the timestamp of
    its latest versioned commit.
-   SVN conflicts are not silently resolved.

If mtime metadata cannot be safely updated, the commit operation is
stopped.

### Update / checkout / revert behavior

After SVN changes a working copy file, SVN Keep MTime reads its
`file:mtime` property and synchronizes the local filesystem timestamp.

A special conflict check is performed when the local timestamp is newer
than the repository metadata. In that situation, the extension reports
the conflict instead of blindly replacing the local timestamp.

## KMT Management

Installing SVN Keep MTime does not automatically scan existing working
copies or change or synchronize their file modification times.

For existing working copies, use `svn kmt` to scan and manage
`file:mtime` metadata.

The main management entry point is:

``` sh
svn kmt
```

The following aliases are also accepted:

``` sh
svn kmt-ui
svn kmt-main
```

The interactive manager provides nine operations:

``` text
1  Scan directories
2  List mtime completed files
3  List mtime completable files
4  List mtime synchronizable files
5  List files with mtime conflicts
6  List mtime unsynchronizable files (file:mtime not completed)
7  Complete file:mtime from local file mtime
8  Synchronize local mtime from repository metadata
9  Resolve mtime conflicts (use local file mtime)
```

Enter any other value to exit the menu.

### Direct management commands

The same operations can be invoked directly:

``` sh
svn kmt-complete
svn kmt-synchronize
svn kmt-sync
svn kmt-resolve
```

These are direct KMT commands, not aliases for the complete interactive
`svn kmt` menu.

## KMT Safety Checks

Before KMT modifying operations:

``` text
kmt-complete
kmt-synchronize
kmt-resolve
```

the selected working copy must be in a suitable SVN state.

The manager checks that:

-   the working copy is up to date with repository HEAD;
-   the SVN schedule is normal;
-   there are no ordinary uncommitted added or modified files;
-   there are no unresolved working-copy conflicts that would interfere
    with the metadata operation.

These checks are intentional. KMT metadata operations must not silently
operate on a working copy while ordinary SVN changes are being made.

The same mtime safety rules used by normal `svn commit` processing also
apply when KMT writes `file:mtime`. In particular, a future local
timestamp is never accepted, and a local timestamp that would violate
the repository timestamp ordering rules is rejected.

## Completing and Synchronizing an Existing Repository

Installing SVN Keep MTime does not automatically add `file:mtime` to
existing repository files, and it does not automatically change
timestamps in existing working copies.

The initialization of an existing repository is a deliberate process:

``` text
Scan
  |
  +--> Completable files --------> Complete
  |
  +--> Synchronizable files -----> Synchronize
  |
  +--> Unsynchronizable files ---> another eligible working copy must Complete
  |
  +--> Conflicts -----------------> Resolve
  |
  v
Completed
```

### The key principle

For a file without `file:mtime`, KMT compares the local filesystem
`mtime` with the file's latest versioned commit timestamp.

Normally, the working copy that still contains the original file
modification time will have:

``` text
local file mtime < latest versioned commit time
```

Such a file is classified as **completable**.

A working copy that does not satisfy this condition is not allowed to
complete the file. It is reported as **unsynchronizable** because the
repository does not yet contain `file:mtime`, so this working copy has
nothing authoritative from which to synchronize its local timestamp.

This means that users do not need to manually decide which host should
complete each file. Each working copy scans its own files, and KMT
determines eligibility per file.

The files that need initialization may therefore be distributed across
many working copies or hosts.

### 1. Make the working copy up to date

Before running a KMT modifying operation:

``` sh
svn update
```

The working copy must be synchronized with repository HEAD and must not
contain ordinary uncommitted changes.

### 2. Scan the working copy

Run:

``` sh
svn kmt
```

Choose:

``` text
1 -- Scan directories
```

The scan classifies versioned files into:

``` text
Completed
Completable
Synchronizable
Conflicts
Unsynchronizable
```

It also reports the number of files in each state.

A useful target state for an initialized working copy is:

``` text
Completed:          all versioned files
Completable:        0
Synchronizable:     0
Conflicts:          0
Unsynchronizable:   0
```

### 3. Complete metadata on eligible working copies

If the scan reports **completable** files, that working copy is eligible
to provide their local file modification times as the original
timestamps.

Choose:

``` text
7 -- Complete file:mtime from local file mtime
```

or run:

``` sh
svn kmt-complete
```

`kmt-complete` does not mean "copy every local mtime into SVN". It only
processes files classified as completable and applies all normal mtime
safety checks.

The resulting `file:mtime` properties are committed to the repository by
the KMT command itself.

A successful completion changes the repository state from:

``` text
file:mtime not completed
```

to:

``` text
file:mtime completed
```

Other working copies will then see those files as **synchronizable** on
their next scan.

### 4. Synchronize other working copies

Once the repository contains `file:mtime`, other working copies can be
synchronized.

Choose:

``` text
8 -- Synchronize local mtime from repository metadata
```

or run:

``` sh
svn kmt-synchronize
```

The compatibility alias is also accepted:

``` sh
svn kmt-sync
```

Synchronization uses:

``` text
repository file:mtime
        |
        v
local filesystem mtime
```

Only files classified as synchronizable are changed.

No SVN commit is required for this operation because it changes the
local filesystem timestamp rather than repository metadata.

### 5. Repeat across working copies

Because the files requiring completion may be distributed across
multiple hosts, each working copy can be scanned independently.

A typical initialization sequence is:

``` text
Host A
  Scan
    -> some files completable
    -> Complete
    -> Commit file:mtime

Host B
  Scan
    -> those files become synchronizable
    -> Synchronize

Host C
  Scan
    -> some other files completable
    -> Complete
    -> Commit file:mtime

All hosts
  Scan
    -> Completed for all initialized files
```

The goal is not to choose one permanent "complete user". Instead, KMT
determines eligibility separately for each file and each working copy.

### Unsynchronizable files

If the scan reports:

``` text
Unsynchronizable
```

the repository does not yet contain `file:mtime` for those files, and
the current working copy is not eligible to complete them.

Those files should be completed from a working copy that still contains
their original file modification times.

After another working copy successfully completes and commits the
metadata:

``` text
Unsynchronizable
        |
        v
file:mtime completed in repository
        |
        v
Synchronizable
```

### Normal operation after initialization

Once the repository and working copies have reached the completed state,
users normally do **not** need to run `kmt-complete` or
`kmt-synchronize` during everyday SVN use.

SVN Keep MTime automatically maintains mtime metadata during normal:

``` text
svn commit
svn update
svn checkout
svn revert
```

operations.

The KMT manager is primarily needed for:

-   initializing an existing repository;
-   inspecting the current mtime state;
-   handling mtime conflicts;
-   checking unusual or incomplete metadata states.

## Resolving Mtime Conflicts

If the local filesystem timestamp and repository metadata disagree,
inspect the conflict first:

``` sh
svn kmt
```

Choose:

``` text
5  List files with mtime conflicts
```

If the local timestamp is intentionally the correct candidate value,
use:

``` text
9  Resolve mtime conflicts (use local file mtime)
```

or:

``` sh
svn kmt-resolve
```

The resolve operation **tries to use** the local filesystem timestamp as
the replacement `file:mtime` value. It does not force the timestamp into
the repository unconditionally. The candidate local timestamp must still
pass the normal mtime safety and consistency checks.

If the local timestamp is not valid, the file remains unresolved and the
user must decide how to handle it.

The resolve operation commits successfully changed metadata.

## Scan Backends

KMT scanning supports three backends:

``` text
python
join
posix
```

Automatic selection is used when no backend is specified:

1.  `python` if Python is available.
2.  `join` if `join` and `awk` are available.
3.  `posix` otherwise.

The backend can be selected explicitly:

``` sh
svn kmt --scan-backend=python
svn kmt --scan-backend=join
svn kmt --scan-backend=posix
```

The option is also accepted by direct KMT commands:

``` sh
svn kmt-complete --scan-backend=join
svn kmt-synchronize --scan-backend=posix
svn kmt-resolve --scan-backend=python
```

`python` and `join` are optimized scanning implementations. `posix` uses
the basic SVN/file iteration path and is the fallback implementation.

## Supported Platforms

The current implementation detects and supports:

-   Linux
-   macOS

Filesystem timestamp operations use platform-specific `stat` and `touch`
commands.

Other operating systems are rejected by the platform check.

## File mtime Property

The property name is fixed as:

``` text
file:mtime
```

The value is stored as a numeric Unix timestamp.

For example:

``` text
file:mtime = 1785921600
```

The property is attached to the versioned path in SVN and is used as the
source of truth when restoring a local timestamp.

## Architecture

The high-level architecture is:

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
     KMT processing      svn_kmt_org
                              |
                              v
                        SVN repository
```

See:

``` text
docs/Architecture.md
```

for the detailed processing flows.

## Development

The main source file is:

``` text
shell/svn_kmt.sh
```

The project is intentionally implemented as a single shell-based SVN
client wrapper.

The source script also contains the installation and upgrade logic. Keep
the source filename:

``` text
svn_kmt.sh
```

because the installer performs an internal filename check.

## Debugging

Internal debug logging can be enabled with:

``` sh
svn --kmt-debug ...
```

or by passing `--kmt-debug` to the wrapper before the SVN/KMT command
arguments.

Debug messages are written to standard error.

## Version

Current version:

``` text
0.7.7
```
