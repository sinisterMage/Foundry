# Publishing a package

Two steps: make a release in your own repository, then add one block here.

## 1. Your package

A package is a directory with an `ingot.toml` and the source it names.

```toml
[package]
name = "acme/json"
version = "1.2.0"
root = "src/json.ws"      # optional; `acme/json` defaults to src/json.ws

[dependencies]
"acme/http" = "^1.0.0"
```

Rules the registry enforces, so it is cheaper to know them now:

- **The name is two lowercase segments**, `owner/name`, each of
  `[a-z0-9][a-z0-9-]*`. Lowercase because a case-insensitive filesystem would
  otherwise make two names one directory; two segments because a bare name in a
  shared registry is a landgrab. `std/…` and `ingot/…` are not available: the
  compiler resolves those before it looks at any package.
- **`version` must match the version you publish here.**
- **`root` must exist.** It is the one file an `@import` of your package
  resolves to — a package presents one file, and what else it shows is what
  that file re-exports.
- **Dependencies must themselves be in this registry.** A published package
  cannot depend on a `path` or a `git` revision, because nobody else can
  resolve those.

Then commit, and note the **full 40-character commit id**. A tag is good
practice and is not what the registry records: a tag can be moved and a commit
cannot.

## 2. The hash

The registry records what your package's tree hashes to, so that everybody who
installs it can check they got the same bytes. Ask `ingot` for it:

```sh
ingot -C path/to/your/package resolve
ingot -C path/to/your/package list
```

The `tree` column of your own package's row is the value — `sha256:` and 64 hex
characters. It is a hash of the *files*, not of the git objects: sorted by
name, with sizes, and with permissions and timestamps deliberately left out,
because a package is its text.

## 3. The pull request

Add or edit exactly two files.

`packages/acme/json/package.toml` — once, when the package is new:

```toml
[package]
name = "acme/json"
repo = "https://github.com/acme/json.git"
description = "JSON, read and written."
```

`repo` must be `https://`. The git client here speaks HTTP and HTTPS and
nothing else — no `ssh://`, no `git@host:path`.

`packages/acme/json/versions.toml` — **append** a block, at the end, because
versions ascend:

```toml
[[version]]
version = "1.2.0"
rev = "8f2c4e1a9b3d5f7061c2a4e6b8d0f2a4c6e8b0d2"
tree = "sha256:9f3ad0…"

[version.dependencies]
"acme/http" = "^1.0.0"
```

Omit `[version.dependencies]` entirely if there are none.

## What CI does with it

`ci/check.ws` runs on the pull request and, for every package it touched:

- fetches `rev` from `repo`, hashes the tree, and insists it is your `tree`;
- reads the `ingot.toml` at that revision and insists it calls itself this
  package and this version;
- insists the file its `root` names is there;
- and checks, over the whole registry, that names are well formed, versions
  ascend, and every requirement names a package that exists here.

If it passes, it is safe to merge: every claim in the index has been checked
against the bytes it describes.

## Afterwards

A published version is never edited. See [POLICY.md](POLICY.md) — a mistake is
a new version, and a withdrawal is `yanked = true`.
