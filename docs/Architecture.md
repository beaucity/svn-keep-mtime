# SVN Keep MTime Architecture

## Overview

SVN Keep MTime is implemented as an SVN client wrapper.

The architecture has two main layers:

```
              User
                |
                v
          svn command
                |
                v
        +----------------+
        |   svn_kmt      |
        +----------------+
          |            |
          |            |
          v            v

   Original SVN     KMT Manager
   svn_kmt_org      file:mtime engine
```

The wrapper keeps normal SVN behavior while adding file modification time management.

---

# Components

## svn_kmt

Main wrapper executable.

Responsibilities:

* intercept SVN commands
* detect SVN operation
* call original SVN client when required
* perform file mtime processing

Installed location:

```
svn_kmt
```

The user normally calls:

```
svn
```

which is linked to:

```
svn_kmt
```

---

## svn_kmt_org

Original SVN executable.

The original SVN binary is preserved after installation:

```
svn_kmt_org
```

The wrapper uses it for actual SVN operations.

---

# KMT Manager

The KMT Manager provides interactive management:

Command:

```
svn kmt
```

or:

```
svn kmt-main
```

Functions include:

* scanning working copy status
* finding missing `file:mtime`
* completing metadata
* restoring filesystem timestamps
* showing affected files

The manager provides a safer workflow for repository migration and maintenance.

---

# File Time Metadata

SVN Keep MTime stores timestamps as SVN properties:

```
file:mtime
```

Example:

```
path/to/file.txt

property:
file:mtime = 20260805120000
```

The property represents the original filesystem modification time.

---

# Commit Flow

Normal commit:

```
svn commit
        |
        v
svn_kmt
        |
        +--> collect file mtime
        |
        +--> set file:mtime property
        |
        v
svn_kmt_org
        |
        v
SVN repository
```

---

# Update Flow

Normal update:

```
svn update
        |
        v
svn_kmt
        |
        v
svn_kmt_org
        |
        v
working copy updated
        |
        v
restore file mtime
```

---

# Migration Flow

For repositories without metadata:

```
Existing repository

       |
       v

svn kmt

       |
       +--> scan files
       |
       +--> generate missing file:mtime
       |
       +--> commit properties
       |
       +--> restore timestamps
```

---

# Command Model

Main command:

```
svn kmt
```

Sub operations:

```
scan
complete
restore
show status
```

Compatibility commands:

```
svn kmt-complete
svn kmt-restore
```

are wrappers around the KMT Manager.

---

# Design Principles

## Non-invasive

No SVN server modification is required.

## Metadata Only

File content is unchanged.

Only SVN properties are added:

```
file:mtime
```

## Safe Processing

Before changing timestamps:

* check working copy state
* check existing metadata
* compare timestamps
* avoid overwriting valid information

## Backward Compatible

Repositories without SVN Keep MTime continue working normally.
