# SVN Keep MTime

SVN Keep MTime (`svn_kmt`) is an SVN client wrapper that preserves filesystem modification time (`mtime`) for versioned files.

SVN itself does not preserve the original filesystem `mtime` as repository metadata. SVN Keep MTime stores the timestamp in the SVN property:

```text
file:mtime
```

The extension works entirely on the SVN client side. It does not require changes to the SVN server or repository format.


## Download

The latest release is available on GitHub Releases.

https://github.com/beaucity/svn-keep-mtime/releases


## Quick Start


```text
# Download the release archive
# Extract it

# Install
cd svn-keep-mtime/shell
chmod +x svn_kmt.sh
./svn_kmt.sh kmt-install

# Use SVN normally
svn checkout <URL>
svn update
svn commit

# Installing SVN Keep MTime does not automatically modify existing repository files.
# Manage existing repositories

svn kmt


```


## Features

- Automatically records local file `mtime` in `file:mtime` when files are committed.
- Automatically restores `file:mtime` to the local filesystem after `update`, `checkout`, and `revert` operations.
- Detects conflicting modification times instead of blindly overwriting them.
- Rejects attempts to commit a future file timestamp.
- Provides a `svn kmt` interactive manager for inspection, migration, restoration, and conflict resolution.
- Supports repositories that were created before SVN Keep MTime was installed.
- Provides multiple scan backends for KMT management operations.
- Keeps the original SVN executable as `svn_kmt_org`.

## How It Works

The basic data flow is:

```text
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

```text
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

```text
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

The extension does not replace normal SVN behavior. The original SVN client still performs the actual SVN operation.

## Installation

The distribution contains:

```text
shell/svn_kmt.sh
```

The installation script **must keep the filename `svn_kmt.sh`**.

Install with:

```sh
./svn_kmt.sh kmt-install
```

The script can also be run as:

```sh
./svn_kmt.sh install
```

After installation, the SVN executable directory contains:

```text
svn -> svn_kmt
svn_kmt
svn_kmt_org
```

`svn` becomes a symbolic link to `svn_kmt`, while the original SVN executable is moved to `svn_kmt_org`.

The installed `svn_kmt` is the client wrapper. It calls `svn_kmt_org` for the actual SVN operation and adds mtime processing where required.

### Link installation mode

By default, the installer copies `svn_kmt.sh` to the installed `svn_kmt`.

For development or local testing, link mode is also available:

```sh
./svn_kmt.sh kmt-install --link
```

In link mode, the installed `svn_kmt` points to the supplied `svn_kmt.sh`.

## Upgrade

Upgrade must be started from the distribution script:

```sh
./svn_kmt.sh kmt-upgrade
```

The installer also accepts:

```sh
./svn_kmt.sh upgrade
```

If an older SVN Keep MTime installation is present, the upgrade process:

1. Uninstalls the current wrapper.
2. Restores the original SVN executable.
3. Installs the new `svn_kmt`.
4. Reconnects `svn` to the new wrapper.

If SVN Keep MTime is not installed, `kmt-upgrade` installs it.

The `svn_kmt.sh` filename check is intentional. Do not rename the distribution installation/upgrade script.

## Uninstall

Uninstall an installed copy with:

```sh
svn kmt-uninstall
```

The uninstall command is intentionally executed through the installed SVN wrapper.

The wrapper:

1. Removes the `svn -> svn_kmt` link.
2. Restores `svn_kmt_org` to `svn`.
3. Removes the installed `svn_kmt`.

After successful uninstall, the normal SVN executable is restored.

Do **not** use the distribution script as the uninstall entry point.

## Normal SVN Usage

After installation, normal SVN commands remain unchanged:

```sh
svn checkout URL
svn update
svn add file
svn commit
svn status
svn revert file
```

SVN Keep MTime currently integrates mtime handling with:

- `commit` / `ci`
- `update` / `up`
- `checkout` / `co`
- `revert`

Other SVN commands are forwarded to the original SVN client without additional KMT processing.

### Commit behavior

Before a commit, SVN Keep MTime examines files reported by `svn status` as added or modified and tries to maintain their `file:mtime` property.

Important safety checks include:

- A future local `mtime` is rejected.
- An existing identical `file:mtime` is left unchanged.
- A modified file cannot replace existing metadata with an earlier timestamp.
- A modified file cannot use an `mtime` earlier than the timestamp of its latest versioned commit.
- SVN conflicts are not silently resolved.

If mtime metadata cannot be safely updated, the commit operation is stopped.

### Update / checkout / revert behavior

After SVN changes a working copy file, SVN Keep MTime reads its `file:mtime` property and restores the filesystem timestamp.

A special conflict check is performed when the local timestamp is newer than the repository metadata. In that situation, the extension reports the conflict instead of blindly replacing the local timestamp.

## KMT Management

Installing SVN Keep MTime does not automatically modify existing repository files.

For existing working copies, use `svn kmt` to scan and complete missing `file:mtime` metadata.

The main management entry point is:

```sh
svn kmt
```

The following aliases are also accepted:

```sh
svn kmt-ui
svn kmt-main
```

The interactive manager provides nine operations:

```text
1  Scan the directories
2  List the completed files
3  List the files needing metadata completion
4  List the files needing mtime restoration
5  List files with mtime conflicts
6  List working-copy files without file:mtime metadata
7  Complete file:mtime metadata
8  Restore local file mtime
9  Resolve mtime conflicts
```

Enter any other value to exit the menu.

### Direct management commands

The same operations can be invoked directly:

```sh
svn kmt-complete
svn kmt-restore
svn kmt-resolve
```

These are direct KMT commands, not aliases for the complete interactive `svn kmt` menu.

## KMT Safety Checks

Before `kmt-complete`, `kmt-restore`, or `kmt-resolve`, the manager checks that each selected working copy is up to date.

It compares:

- the local working-copy revision
- the repository HEAD revision

It also requires the selected working copy to have a normal SVN schedule.

For these modifying KMT operations, local uncommitted changes are not allowed. If added, modified, or conflicted working files are detected, the operation stops and asks the user to commit or resolve the changes first.

This is intentional: KMT metadata operations should not interfere with ordinary user changes.

## Completing Existing Repositories

Installing SVN Keep MTime does not automatically add `file:mtime` to every existing repository file.

For an existing working copy:

### 1. Make sure it is up to date

```sh
svn update
```

### 2. Inspect the working copy

```sh
svn kmt
```

Choose:

```text
1  Scan
```

The scan reports:

- completed files
- files that can be completed
- files that should be restored
- mtime conflicts
- working-copy files without metadata

### 3. Complete missing metadata

Choose:

```text
7  Complete file:mtime metadata
```

For files without `file:mtime`, the manager compares the local filesystem `mtime` with the versioned commit timestamp.

A missing metadata entry is completed only when the timestamp passes the manager's safety rules. A file whose local timestamp is not suitable is reported rather than blindly written.

The generated `file:mtime` properties are then committed by the KMT command itself.

### 4. Restore local timestamps

Choose:

```text
8  Restore local file mtime
```

This applies the repository's `file:mtime` values to the local files.

## Resolving Mtime Conflicts

If the local filesystem timestamp and repository metadata disagree, inspect the conflict first:

```sh
svn kmt
```

Choose:

```text
5  List files with mtime conflicts
```

If the local timestamp is intentionally the correct value, use:

```text
9  Resolve mtime conflicts
```

or:

```sh
svn kmt-resolve
```

The resolve operation attempts to replace the repository `file:mtime` value with the local filesystem timestamp, subject to the same safety checks used when saving metadata.

The resolve operation commits the changed metadata.

## Scan Backends

KMT scanning supports three backends:

```text
python
join
posix
```

Automatic selection is used when no backend is specified:

1. `python` if Python is available.
2. `join` if `join` and `awk` are available.
3. `posix` otherwise.

The backend can be selected explicitly:

```sh
svn kmt --scan-backend=python
svn kmt --scan-backend=join
svn kmt --scan-backend=posix
```

The option is also accepted by direct KMT commands:

```sh
svn kmt-complete --scan-backend=join
svn kmt-restore --scan-backend=posix
svn kmt-resolve --scan-backend=python
```

`python` and `join` are optimized scanning implementations. `posix` uses the basic SVN/file iteration path and is the fallback implementation.

## Supported Platforms

The current implementation detects and supports:

- Linux
- macOS

Filesystem timestamp operations use platform-specific `stat` and `touch` commands.

Other operating systems are rejected by the platform check.

## File mtime Property

The property name is fixed as:

```text
file:mtime
```

The value is stored as a numeric Unix timestamp.

For example:

```text
file:mtime = 1785921600
```

The property is attached to the versioned path in SVN and is used as the source of truth when restoring a local timestamp.

## Architecture

The high-level architecture is:

```text
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

```text
docs/Architecture.md
```

for the detailed processing flows.

## Development

The main source file is:

```text
shell/svn_kmt.sh
```

The project is intentionally implemented as a single shell-based SVN client wrapper.

The source script also contains the installation and upgrade logic. Keep the source filename:

```text
svn_kmt.sh
```

because the installer performs an internal filename check.

## Debugging

Internal debug logging can be enabled with:

```sh
svn --kmt-debug ...
```

or by passing `--kmt-debug` to the wrapper before the SVN/KMT command arguments.

Debug messages are written to standard error.

## Version

Current version:

```text
0.7.6
```
