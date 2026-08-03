# SVN Keep MTime Architecture

## 1. Overview

SVN Keep MTime (`svn_kmt`) is an SVN wrapper extension designed to
preserve file modification time (`mtime`) information during SVN
operations.

The main goal is:

-   Keep file timestamps consistent between different SVN clients.
-   Preserve original SVN behavior.
-   Add mtime management without modifying the original SVN executable.

The project is implemented entirely using POSIX shell script.

------------------------------------------------------------------------

# 2. Design Goals

## 2.1 Preserve Original SVN

SVN Keep MTime does not replace SVN.

The original SVN executable is kept unchanged and renamed to:

    svn_org

The wrapper forwards normal SVN commands to the original SVN executable.

Architecture:

    User
     |
     v
    svn
     |
     v
    svn_kmt
     |
     v
    svn_kmt_org
     |
     v
    Original SVN

------------------------------------------------------------------------

## 2.2 Store File Modification Time as SVN Metadata

SVN does not normally preserve file modification time after checkout or
update.

SVN Keep MTime stores timestamps using SVN properties:

    file
     |
     +-- file:mtime

Example:

    source.c

    Properties:

    file:mtime = 2026-01-01 10:30:00

The timestamp becomes part of repository metadata and can be
synchronized between clients.

------------------------------------------------------------------------

# 3. Main Components

## 3.1 svn_kmt.sh

The main shell script provides:

-   SVN command wrapper
-   mtime processing
-   installation management
-   upgrade management
-   uninstall management

------------------------------------------------------------------------

## 3.2 Original SVN Detection

During installation:

    svn
     |
     +-- original SVN executable

is moved to:

    svn_org

The wrapper then becomes the new `svn` entry point.

The original executable is never modified.

------------------------------------------------------------------------

# 4. Installation Architecture

Installation command:

``` bash
./svn_kmt.sh kmt-install
```

Before installation:

    svn
     |
     +-- original SVN

After installation:

    svn
     |
     +-- svn_kmt

    svn_kmt_org
     |
     +-- original SVN

All normal SVN commands are handled by `svn_kmt`.

------------------------------------------------------------------------

# 5. Upgrade Architecture

Upgrade command:

``` bash
./svn_kmt.sh kmt-upgrade
```

The upgrade command must be executed from the new `svn_kmt.sh` file.

It is intentionally not:

``` bash
svn kmt-upgrade
```

because the installed `svn` command may still point to the old wrapper
version.

Upgrade process:

    New svn_kmt.sh
            |
            v
    kmt-upgrade
            |
            v
    kmt-uninstall
            |
            v
    restore original SVN
            |
            v
    kmt-install
            |
            v
    new wrapper installed

The upgrade process reuses the tested install and uninstall logic.

------------------------------------------------------------------------

# 6. Runtime Processing

## 6.1 Commit Processing

During commit:

    Working copy file
            |
            v
    Read file modification time
            |
            v
    Save as file:mtime property
            |
            v
    SVN commit

Only metadata is handled by SVN Keep MTime.

Normal file content changes are handled by SVN itself.

------------------------------------------------------------------------

## 6.2 Update / Checkout Processing

During update or checkout:

    SVN repository

    file:mtime property
            |
            v
         svn_kmt
            |
            v
    Restore filesystem timestamp

The working copy receives the original modification time.

------------------------------------------------------------------------

# 7. Existing Repository Migration

SVN Keep MTime can also be used with existing repositories.

Before installation:

    Client A:

    file.txt
    mtime = 10:00


    Client B:

    file.txt
    mtime = 12:00

The repository does not contain timestamp information.

Migration:

## Step 1

Generate mtime metadata:

``` bash
svn kmt-complete
```

This reads current file timestamps and creates:

    file:mtime

properties.

## Step 2

Restore timestamps on other clients:

``` bash
svn kmt-restore
```

The timestamp information is restored from SVN properties.

Migration is optional and can be performed when required.

------------------------------------------------------------------------

# 8. Command Architecture

## SVN Commands

### Version

``` bash
svn kmt-version
```

Display SVN Keep MTime version.

------------------------------------------------------------------------

### Complete mtime

``` bash
svn kmt-complete
```

Create `file:mtime` properties for existing files.

Requirements:

-   Working copy must not contain uncommitted changes.
-   Only mtime metadata is processed.

------------------------------------------------------------------------

### Restore mtime

``` bash
svn kmt-restore
```

Restore file modification time from SVN properties.

------------------------------------------------------------------------

## Management Commands

### Install

``` bash
./svn_kmt.sh kmt-install
```

Install SVN Keep MTime.

------------------------------------------------------------------------

### Upgrade

``` bash
./svn_kmt.sh kmt-upgrade
```

Upgrade SVN Keep MTime.

------------------------------------------------------------------------

### Uninstall

``` bash
svn kmt-uninstall
```

Remove SVN Keep MTime.

Uninstall is intentionally executed through the installed SVN wrapper
to guarantee that the operation is performed by the currently active
SVN Keep MTime installation.

------------------------------------------------------------------------

## Installation States

Before installation:

svn
 |
 +-- original SVN


After installation:

svn
 |
 +-- svn_kmt

svn_kmt_org
 |
 +-- original SVN


After uninstall:

svn
 |
 +-- original SVN

------------------------------------------------------------------------

# 9. Error Handling Design

Installation and upgrade operations include rollback handling.

Examples:

-   Failed copy operation
-   Failed permission change
-   Failed symbolic link creation

The goal is:

-   Avoid leaving SVN unusable.
-   Restore original SVN when possible.

------------------------------------------------------------------------

# 10. Compatibility

SVN Keep MTime uses POSIX shell features.

Supported environments:

-   macOS
-   Linux

No Python runtime is required.

------------------------------------------------------------------------

# 11. Design Principles

## Simple

The project uses shell only to reduce deployment complexity.

## Safe

The original SVN executable is preserved.

## Transparent

Normal SVN commands continue to work without user changes.

## Minimal

Only file modification time management is added.
