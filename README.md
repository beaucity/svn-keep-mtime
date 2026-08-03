# SVN Keep MTime

SVN Keep MTime (`svn_kmt`) is an SVN extension tool that preserves file
modification time (mtime) between SVN clients.

## Overview

Subversion normally does not preserve the original file modification
time when files are checked out or updated. Different clients may
therefore have different timestamps for the same repository files.

SVN Keep MTime solves this problem by storing file modification time
information in SVN properties:

    file
     |
     +-- file:mtime

The tool is implemented entirely with POSIX shell script and does not
require Python or additional runtime dependencies.

## Features

-   Keep file modification time synchronized through SVN
-   Automatically save mtime information during commit
-   Automatically restore mtime during update and checkout
-   Support existing repository timestamp migration
-   Pure shell implementation
-   Compatible with macOS and Linux
-   Keep the original SVN executable unchanged

## Architecture

SVN Keep MTime works as an SVN wrapper.

After installation:

    svn
     |
     v
    svn_kmt.sh
     |
     v
    svn_kmt_org
     |
     v
    original SVN executable

The original SVN executable is renamed to `svn_kmt_org`. SVN Keep MTime
forwards normal SVN operations to the original executable while adding
mtime handling.

## Installation

Download the script:

``` bash
chmod +x svn_kmt.sh
```

Install:

``` bash
./svn_kmt.sh kmt-install
```

## Upgrade

Upgrade must be executed from the new script:

``` bash
./svn_kmt.sh kmt-upgrade
```

Do not use:

``` bash
svn kmt-upgrade
```

because upgrade uses the current `svn_kmt.sh` as the installation
source.

The upgrade process:

1.  Remove the current SVN Keep MTime wrapper installation
2.  Restore the original SVN executable
3.  Install the new script
4.  Recreate the SVN wrapper

## Uninstall

Remove SVN Keep MTime:

``` bash
svn kmt-uninstall
```

The original SVN executable will be restored.

The uninstall command must be executed through the installed svn wrapper.

Do not run:

./svn_kmt.sh kmt-uninstall

because it may execute a different svn_kmt.sh version that is not currently active.


## Existing Repository Migration

If a repository was created before installing SVN Keep MTime, existing
clients may already have different file modification times.

Migration is optional. It can be performed later according to user
requirements.

Use:

``` bash
svn kmt_complete
```

to create `file:mtime` properties from the current working copy.

Before running:

-   The working copy must not contain uncommitted changes.
-   This command only handles mtime metadata.
-   It does not commit normal file content changes.

After the metadata has been stored:

``` bash
svn kmt_restore
```

can restore file modification times from SVN properties.

## Daily Usage

After installation, normal SVN operations do not require additional
commands.

Examples:

``` bash
svn update
svn commit
svn checkout
```

SVN Keep MTime automatically:

-   Saves file mtime during commit
-   Restores file mtime during update and checkout

Users do not need to manually run `kmt_restore` during normal
operation.

## Commands

Show version:

``` bash
svn kmt-version
```

Complete existing file mtime:

``` bash
svn kmt_complete
```

Restore file mtime:

``` bash
svn kmt_restore
```

Install:

``` bash
./svn_kmt.sh kmt-install
```

Upgrade:

``` bash
./svn_kmt.sh kmt-upgrade
```

Uninstall:

``` bash
./svn_kmt.sh kmt-uninstall
```

## Requirements

-   SVN client
-   POSIX compatible shell

Tested environments:

-   macOS
-   Linux

No Python dependency is required.

## Design Principles

### Do not modify original SVN

The original SVN executable is preserved and called through the wrapper
mechanism.

### Minimal extension

SVN Keep MTime only manages file timestamp metadata and does not replace
SVN functionality.

### Simple deployment

The project uses shell only to keep deployment simple and
dependency-free.

## License

See LICENSE file.
