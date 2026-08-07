# AGENTS.md

# SVN Keep MTime Development Guide

## Project Overview

SVN Keep MTime (`svn_kmt`) is an SVN client extension that preserves file modification time metadata.

The implementation is shell based and works by wrapping the original SVN client.

Main executable:

```
svn_kmt.sh
```

Installed executable:

```
svn_kmt
```

---

# Architecture Rules

The project contains two major parts:

## SVN Wrapper

Responsible for:

* intercepting SVN commands
* forwarding commands to original SVN
* integrating mtime processing

## KMT Manager

Responsible for:

* file time analysis
* metadata completion
* timestamp restoration
* user interaction

Main command:

```
svn kmt
```

---

# Command Naming Rules

Current command style:

```
kmt-xxxx
```

Examples:

```
svn kmt-install
svn kmt-uninstall
svn kmt-upgrade
svn kmt-version
```

User management command:

```
svn kmt
```

or:

```
svn kmt-main
```

---

# File Naming Rules

Installation script:

```
svn_kmt.sh
```

must keep this name.

It is responsible for:

* installation
* upgrade
* initial deployment

Do not rename:

```
svn_kmt.sh
```

The script performs internal name checks.

Installed files:

```
svn_kmt
svn_kmt_org
```

---

# Metadata Rules

The project uses SVN property:

```
file:mtime
```

Rules:

* never overwrite existing valid metadata
* only create missing metadata when safe
* restore local timestamps only from trusted metadata

---

# Testing Requirements

Before submitting changes:

Test on:

* macOS
* Linux

Check:

* normal SVN commands
* install
* uninstall
* upgrade
* `svn kmt`
* metadata completion
* timestamp restoration

---

# Documentation Requirements

When changing:

* commands
* installation flow
* architecture
* user workflow

Update:

```
README.md
docs/Architecture.md
AGENTS.md
```

Command examples must use the current naming convention.

---

# Development Principles

## Keep SVN Compatible

The extension must behave like normal SVN.

## Avoid Repository Changes

Only SVN properties may be added.

## Prefer Safe Operations

When uncertain:

* report status
* ask user
* do not modify timestamps automatically

## Keep User Workflow Simple

The preferred user entry point is:

```
svn kmt
```

not individual internal commands.
