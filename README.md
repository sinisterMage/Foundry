# Foundry

The package registry for [W#](https://github.com/sinisterMage/WSharp). A
foundry is where ingots are cast.

This repository is an **index**, not a store of code. It records, for each
published version of each package, where its source is and what it depends on.
The source stays in the package's own git repository; `ingot` fetches it from
there and keeps it in a content-addressed store under `~/.wsharp`.

**Packages are W# source.** Nothing here is compiled and no binary is ever
published — `wsharp build` is ahead-of-time, so the machine that installs a
package is the machine that compiles it, and a registry shipping artifacts
would be shipping the one thing this toolchain does not need.

## Using it

Nothing to set up: this is where `ingot` looks by default.

```sh
ingot add acme/json          # the newest version, as a caret requirement
ingot add acme/json ^1.2.0   # or say which
ingot resolve                # choose versions and write ingot.lock
ingot install                # fetch them and make the store satisfy it
ingot search json            # what is published
ingot update                 # fetch this index again
```

`INGOT_REGISTRY` points somewhere else — a URL, or a **directory**, which is
used where it lies and never fetched. A registry is a directory; cloning this
one over git is only how the directory arrives. That is what a private registry
is, and what an offline one is.

Requires `wsharp`/`ingot` **0.1.1 or newer**. Earlier versions have no registry
and refuse a version dependency by name.

## Layout

```
Registry.toml                          the name, and the format version
packages/<owner>/<name>/package.toml   the name, and where to fetch it from
packages/<owner>/<name>/versions.toml  one [[version]] per release
```

A package is a directory holding a `package.toml`; anything else under
`packages/` is a namespace. That rule is why there is no central list of
contents — a file every pull request would conflict on.

`packages/acme/json/package.toml`:

```toml
[package]
name = "acme/json"
repo = "https://github.com/acme/json.git"
description = "JSON, read and written."
```

`packages/acme/json/versions.toml`:

```toml
[[version]]
version = "1.2.0"
rev = "8f2c4e1a…"                      # the commit, as a full object id
tree = "sha256:9f3ad0…"                # what that commit's tree hashes to

[version.dependencies]
"acme/http" = "^1.0.0"
```

**`tree` is the point.** It is `ingot`'s own tree hash — the key the package
gets in the store — so `ingot resolve` writes a lockfile without fetching
anything, and the fetch `ingot install` does afterwards is checked against a
hash this registry committed to. The client trusts a hash rather than a host,
and CI is what makes that hash a promise rather than a hope: every entry a pull
request adds is fetched at its revision and hashed before it is merged.

## Publishing

See [docs/PUBLISHING.md](docs/PUBLISHING.md), and
[docs/POLICY.md](docs/POLICY.md) for the rules — naming, immutability, and what
yanking does.

The short version: tag a release in your own repository, then open a pull
request here adding one `[[version]]` block.

## Checking it

The validator is itself a W# program, and it imports the same reader the client
uses, so there is no second implementation of this format:

```sh
wsharp run ci/check.ws                                    # structure, offline
wsharp run ci/check.ws -- packages/acme/json/versions.toml # and fetch that one
```

## Licence

MIT, as W# is. The packages it indexes are their authors', under their own
terms.
