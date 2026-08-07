# SVN Keep MTime

SVN Keep MTime (`svn_kmt`) is an SVN client extension that preserves file modification time (`mtime`) information through SVN operations.

The project extends the standard SVN client without changing the repository format or SVN server. It stores file modification timestamps in SVN properties and automatically restores local file timestamps when needed.

## Features

* Preserve file modification time after SVN update/checkout.
* Store original file modification time as SVN property:

```
file:mtime
```

* Automatically maintain metadata during normal SVN operations.
* Provide interactive file time management through:

```
svn kmt
```

* Support migration of existing repositories.

## How It Works

SVN normally records file content and version history, but does not preserve the original filesystem modification time.

SVN Keep MTime adds a metadata layer:

```
Working Copy
     |
     |
     v
file modification time
     |
     |
     v
SVN property

file:mtime
```

During commit:

```
local mtime
     |
     v
file:mtime property
     |
     v
SVN repository
```

During update:

```
SVN repository
     |
     v
file:mtime property
     |
     v
restore local file mtime
```

## Installation

Install using:

```
./svn_kmt.sh kmt-install
```

After installation:

```
svn
 |
 -> svn_kmt
 |
 -> svn_kmt_org
```

The original SVN client is preserved as:

```
svn_kmt_org
```

The extension works as an SVN client wrapper.

## Daily Usage

After installation, normal SVN commands continue to work:

```
svn checkout
svn update
svn add
svn commit
svn status
```

No special workflow is required.

SVN Keep MTime automatically handles:

* collecting file modification time metadata
* submitting metadata during commit
* restoring timestamps after update

## File Time Management

For existing repositories or troubleshooting, use:

```
svn kmt
```

or:

```
svn kmt-main
```

The command provides an interactive management interface.

Typical workflow:

```
svn kmt

1. Scan files
2. Review missing metadata
3. Complete file:mtime metadata
4. Commit metadata
5. Restore local file time
```

## Migration Existing Repository

For repositories created before installing SVN Keep MTime:

### 1. Check status

```
svn kmt
```

Review files without `file:mtime`.

### 2. Complete metadata

Use the interactive menu to generate missing metadata.

The command checks:

* current working copy status
* existing `file:mtime`
* local modification time
* repository commit time

Only safe files are processed.

### 3. Commit metadata

Commit generated properties:

```
svn commit
```

### 4. Restore file timestamps

Restore local filesystem timestamps from SVN metadata:

```
svn kmt
```

Select restore operation.

## Commands

### KMT Management

```
svn kmt
svn kmt-main
```

Interactive file modification time management.

### Compatibility Commands

```
svn kmt-complete
svn kmt-restore
```

These commands remain available as direct shortcuts.

Equivalent operations:

```
svn kmt-complete
```

equals:

```
svn kmt
```

select complete metadata.

```
svn kmt-restore
```

equals:

```
svn kmt
```

select restore file timestamps.

### Installation

The installation script:

```
svn_kmt.sh
```

supports:

```
./svn_kmt.sh kmt-install
./svn_kmt.sh kmt-upgrade
```

### Remove

Use:

```
svn kmt-uninstall
```

The uninstall command must be executed through the installed SVN wrapper.

## Architecture

See:

```
docs/Architecture.md
```

## Version

Current version:

```
0.7.0
```
