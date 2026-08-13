# AGENTS.md

# SVN Keep MTime Development Guide

## 1. Project Overview

SVN Keep MTime (`svn_kmt`) is a client-side SVN wrapper for preserving filesystem modification time (`mtime`) through SVN operations.

The current implementation is shell based and is contained in:

```text
shell/svn_kmt.sh
```

The source script provides:

- SVN wrapper behavior;
- KMT metadata processing;
- interactive KMT management;
- installation;
- uninstall;
- upgrade;
- version reporting.

Current version:

```text
0.7.5
```

---

## 2. Core Metadata

The only KMT repository property is:

```text
file:mtime
```

Its value is a Unix timestamp.

The property represents the filesystem modification time that KMT wants to preserve across SVN operations.

Do not introduce a second property for the same purpose without an explicit architecture decision.

---

## 3. Installation Architecture

The distribution script must remain:

```text
svn_kmt.sh
```

The installed files are:

```text
svn
svn_kmt
svn_kmt_org
```

After installation:

```text
svn -> svn_kmt
```

and:

```text
svn_kmt_org
```

is the original SVN executable.

### Important naming rule

Do not rename:

```text
svn_kmt.sh
```

The dispatcher explicitly checks this filename before allowing installation and upgrade.

The installed executable is:

```text
svn_kmt
```

not `svn_kmt.sh`.

---

## 4. Command Naming

Current public KMT commands:

```text
svn kmt
svn kmt-ui
svn kmt-main

svn kmt-complete
svn kmt-restore
svn kmt-resolve

svn kmt-version
svn kmt-uninstall
```

Distribution-script commands:

```text
./svn_kmt.sh kmt-install
./svn_kmt.sh kmt-install --link
./svn_kmt.sh kmt-upgrade
```

Compatibility aliases currently accepted by the dispatcher include:

```text
install
upgrade
```

and the KMT UI aliases:

```text
kmt-ui
kmt-main
```

Do not document obsolete underscore command names such as:

```text
kmt_complete
kmt_restore
```

---

## 5. SVN Operations with KMT Processing

The wrapper currently intercepts:

```text
commit / ci
update / up
checkout / co
revert
```

Other SVN commands are normally forwarded to the original SVN executable.

When changing the intercepted command set, update:

```text
README.md
docs/Architecture.md
```

and test the dispatcher.

---

## 6. Commit Metadata Rules

Before a normal SVN commit, KMT examines added and modified files.

The local filesystem mtime may be stored as `file:mtime`, but only after safety checks.

### Required rules

1. Never commit a future timestamp.
2. If the existing property already equals the local timestamp, do not rewrite it.
3. Do not move existing metadata backwards for a modified file.
4. Do not use a modified file's timestamp when it is earlier than the latest versioned commit timestamp.
5. Do not silently ignore SVN conflicts.
6. If mtime metadata cannot be safely maintained, stop the commit operation.

These rules are implemented primarily in:

```text
save_a_file_mtime()
```

and:

```text
save_file_mtime()
```

---

## 7. Update / Checkout / Revert Rules

After the original SVN operation produces relevant path changes, KMT reads:

```text
file:mtime
```

and restores the local filesystem timestamp.

The implementation must not blindly overwrite a newer local timestamp when the update state indicates an mtime conflict.

The main output processing is implemented in:

```text
svn_hook_line()
```

and timestamp restoration is implemented in:

```text
restore_a_file_mtime()
```

---

## 8. KMT Manager

The preferred user entry point is:

```text
svn kmt
```

The interactive menu currently provides:

```text
1  Scan
2  Show completed
3  Show files to complete
4  Show files to restore
5  Show mtime conflicts
6  Show working-copy files without metadata
7  Complete metadata
8  Restore local mtime
9  Resolve mtime conflicts
```

The internal KMT operation names are:

```text
scan
show_completed
show_to_complete
show_to_restore
show_conflict
show_working_copy
complete
restore
resolve
```

Direct commands map to:

```text
kmt-complete -> complete
kmt-restore  -> restore
kmt-resolve  -> resolve
```

---

## 9. KMT Safety Requirements

Before:

```text
complete
restore
resolve
```

the selected working copy must:

- have a normal SVN schedule;
- be at least as new as repository HEAD;
- have no uncommitted added/modified/conflicted files.

The purpose is to prevent KMT metadata operations from interfering with normal user work.

Do not weaken these checks without updating the architecture and test strategy.

---

## 10. Scan Backend Rules

Three scanner backends exist:

```text
python
join
posix
```

Automatic selection is:

```text
python
    |
    +-- if python exists

join
    |
    +-- if join and awk exist and python is unavailable

posix
    |
    +-- fallback
```

The backend can be selected through:

```text
--scan-backend=python
--scan-backend=join
--scan-backend=posix
--scan-backend=auto
```

When changing scanner behavior, all supported backends must produce equivalent classification results.

Performance changes should not change mtime safety decisions.

---

## 11. Scanner Data Contract

The scanner feeds the KMT decision engine four values:

```text
file
file_ts
prop_ts
version_ts
```

Where:

```text
file_ts     = local filesystem mtime
prop_ts     = file:mtime SVN property, if present
version_ts  = latest versioned commit timestamp, when needed
```

The central classification logic is:

```text
on_scan()
```

Keep scanner implementations separate from classification logic where possible.

This allows scanner performance to improve without changing KMT semantics.

---

## 12. Platform Support

Current supported platforms:

```text
Linux
macOS
```

Platform-specific filesystem operations are handled by:

```text
get_file_mtime()
set_file_mtime()
```

Do not add platform-specific commands directly to unrelated KMT logic.

If another platform is added, update:

```text
detect_platform()
get_file_mtime()
set_file_mtime()
```

and add platform tests.

---

## 13. Code Organization

The main functional areas in `svn_kmt.sh` are:

```text
Configuration
Utility
Platform
Original SVN Detection
Installation / Uninstall / Upgrade
SVN API
Time Functions
Working Copy Functions
Scanning
KMT Classification
Save File Mtime
Restore File Mtime
Command Handler
KMT Command Handler
Working Copy Update Check
KMT UI
Version
Dispatcher
Main
```

Keep the implementation grouped by responsibility.

---

## 14. Installation Safety

Installation moves the original SVN executable to:

```text
svn_kmt_org
```

and creates:

```text
svn -> svn_kmt
```

The installer contains rollback behavior for important failure points.

Changes to installation logic must preserve the following invariant:

```text
If installation fails, do not intentionally leave the user without the original SVN executable.
```

Upgrade is implemented as:

```text
uninstall old version
        |
        v
install new version
```

The upgrade entry point must remain:

```text
./svn_kmt.sh kmt-upgrade
```

---

## 15. Uninstall Rule

The supported uninstall command is:

```text
svn kmt-uninstall
```

The command must be run through the installed wrapper.

The uninstall logic restores:

```text
svn_kmt_org -> svn
```

before removing:

```text
svn_kmt
```

Do not change this flow without testing both successful uninstall and rollback behavior.

---

## 16. Testing Requirements

At minimum, test on:

```text
macOS
Linux
```

### SVN wrapper tests

Test:

```text
svn checkout
svn update
svn commit
svn revert
svn status
```

### KMT command tests

Test:

```text
svn kmt
svn kmt-complete
svn kmt-restore
svn kmt-resolve
svn kmt-version
```

### Installation tests

Test:

```text
kmt-install
kmt-install --link
kmt-upgrade
kmt-uninstall
```

### Timestamp tests

Test at least:

```text
mtime == file:mtime
mtime > file:mtime
mtime < file:mtime
missing file:mtime
future mtime
mtime earlier than latest version timestamp
```

### Working-copy state tests

Test:

```text
up-to-date working copy
out-of-date working copy
modified files
added files
conflicted files
```

### Scanner tests

The following backends should produce equivalent classifications:

```text
python
join
posix
```

when the required tools are available.

---

## 17. Documentation Requirements

When changing behavior, update:

```text
README.md
docs/Architecture.md
```

When changing development conventions, source layout, command names, installation behavior, or testing requirements, update:

```text
AGENTS.md
```

Documentation must reflect the actual implementation in `shell/svn_kmt.sh`.

Do not document planned behavior as current behavior.

---

## 18. Development Principles

### Preserve SVN compatibility

Normal SVN commands should continue to behave as normal SVN commands unless KMT explicitly needs to add mtime handling.

### Keep metadata conservative

`file:mtime` becomes repository data. Incorrect timestamps can propagate to other working copies, so uncertain cases should stop or be reported.

### Keep scanner and decision logic separate

Scanner implementations may change for performance, but the classification and safety rules should remain stable.

### Avoid unnecessary repository changes

KMT should only add or modify the `file:mtime` property required to preserve mtime.

### Prefer explicit failure over silent corruption

If an operation cannot safely determine what timestamp should be used, report the problem and stop.

### Keep the user workflow simple

The preferred management command is:

```text
svn kmt
```

Direct commands exist for scripting and convenience:

```text
svn kmt-complete
svn kmt-restore
svn kmt-resolve
```
