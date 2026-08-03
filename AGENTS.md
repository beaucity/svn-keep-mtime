# AGENTS.md

## Project Overview

This project is SVN Keep MTime (`svn_kmt`).

SVN Keep MTime is an SVN wrapper extension implemented entirely with
POSIX shell script. It preserves file modification time (`mtime`)
information between SVN clients by storing timestamps as SVN properties.

The project does not modify SVN itself. It wraps the original SVN
executable and adds mtime management.

------------------------------------------------------------------------

## Architecture Rules

### Shell Only

The implementation uses POSIX shell.

Avoid introducing:

-   Python scripts
-   Bash-only syntax
-   Additional runtime dependencies
-   Python dependencies
-   non-portable shell extensions

unless compatibility impact has been reviewed.

Supported environments:

-   macOS
-   Linux

------------------------------------------------------------------------

## SVN Wrapper Model

Installation architecture:

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

Rules:

-   Never modify the original SVN executable.
-   Preserve it as `svn_kmt_org`.
-   Keep normal SVN behavior transparent.

------------------------------------------------------------------------

## File MTime Design

The timestamp metadata is stored as:

    file:mtime

Rules:

-   Commit operations save mtime information.
-   Update and checkout operations restore mtime.
-   Normal SVN content management remains unchanged.

------------------------------------------------------------------------

## Existing Repository Migration

Migration commands:

    svn kmt_complete
    svn kmt_restore

Rules:

-   Migration is optional.
-   It is not required for normal daily usage.
-   `kmt_complete` only manages mtime metadata.
-   It must not encourage users to commit unrelated file changes.

Before running `kmt_complete`:

-   Working copy must not contain uncommitted changes.

------------------------------------------------------------------------

## Management Commands

### Install

    ./svn_kmt.sh kmt-install

Responsibilities:

-   Detect original SVN.
-   Preserve original executable.
-   Install wrapper.
-   Provide rollback on failure.

### Upgrade

    ./svn_kmt.sh kmt-upgrade

Upgrade must be executed from the new `svn_kmt.sh`.

Do not use:

    svn kmt-upgrade

because the installed wrapper may be an older version.

Upgrade workflow:

    kmt-uninstall
            |
            v
    restore original SVN
            |
            v
    kmt-install

### Uninstall

    svn kmt-uninstall

Restore the original SVN executable.

The uninstall operation must be executed through the installed SVN wrapper.

Do not use:

./svn_kmt.sh kmt-uninstall

because the script may not be the active installed version.

------------------------------------------------------------------------

## Code Style

Prefer:

-   POSIX shell syntax
-   portable commands
-   explicit return checking

Check important operations:

-   cp
-   mv
-   rm
-   chmod
-   ln

Provide clear error messages and rollback when possible.

------------------------------------------------------------------------

## User Output

Messages should be:

-   concise;
-   grammatically correct;
-   consistent.

Use terminology:

-   SVN Keep MTime
-   svn_kmt
-   original SVN
-   file:mtime

Do not use obsolete names:

-   svn_ext
-   SVN Extension

------------------------------------------------------------------------

## Testing Requirements

Test before release:

### Platforms

-   macOS
-   Linux

### Shells

-   zsh
-   dash/bash compatible shells

### Scenarios

-   fresh install
-   failed install rollback
-   upgrade
-   uninstall
-   checkout
-   update
-   commit
-   mtime restoration
-   existing repository migration

------------------------------------------------------------------------

## Documentation

Keep synchronized:

    README.md
    Architecture.md
    AGENTS.md

Update documentation when changing:

-   commands
-   architecture
-   installation flow
-   user workflow

------------------------------------------------------------------------

## Release Checklist

Before release:

-   Verify version number.
-   Verify command names.
-   Review English output messages.
-   Test macOS/Linux compatibility.
-   Confirm rollback behavior.
-   Confirm documentation matches implementation.
