# Policy

Four rules. Each is here because something breaks without it, and the reason is
written down rather than assumed.

## A published version is never edited

Once a `[[version]]` block is merged, its `version`, `rev` and `tree` do not
change. Not to fix a typo, not to repoint at a better commit.

This is not tidiness. `ingot` memoises a source string to a tree digest and
never invalidates that memo, because `reg+acme/json@1.2.0` is supposed to name
one tree for ever — so a version edited after the fact would be a stale entry on
every machine that had already fetched it, with nothing able to clear it. Worse,
the people who would keep the old bytes are exactly the people who already
depend on you.

A mistake is a **new version**. That is what patch numbers are.

The one permitted edit to an existing block is adding `yanked = true`.

## Yanking withdraws a version from being chosen, not from existing

```toml
[[version]]
version = "1.2.0"
rev = "…"
tree = "sha256:…"
yanked = true
```

A yanked version is not offered to the resolver: `ingot add` will not pick it,
and a fresh `ingot resolve` will not choose it. It stays readable, so a
lockfile that already names it still installs. Breaking those builds is what
deleting the entry would do, and a registry that can retroactively break a
build somebody already shipped is not one worth depending on.

Yank when a version is broken or was published in error. Yanking is not how a
security problem is fixed — publish the fix as a new version *and* yank the bad
one, so that people are moved forward rather than merely stopped.

## Names

Two lowercase segments, `owner/name`, each `[a-z0-9][a-z0-9-]*`, with the
hyphen never leading.

- **Lowercase**, because macOS and Windows have case-insensitive filesystems and
  a registry that means different things on different machines cannot be
  checked.
- **Two segments**, because a bare name in a shared registry is a landgrab. The
  owner segment is yours to organise; nobody arbitrates a global `json`.
- **Not `std` or `ingot`**, because the compiler resolves those namespaces
  before it looks at any package. Such a package would install and then be
  unreachable, which is the worst shape a failure takes.

A name is a directory path here, which is the other reason it is checked before
it is used.

## What is not indexed

`description` is the only prose the index carries, and it is not searched
beyond the name. There are no keywords, no categories, no download counts, no
ownership records and no accounts: this is a git repository, and who may change
an entry is who may merge a pull request to it. If that stops being enough, the
answer is a policy written here and enforced by CI, not a database.

Permissions and timestamps are not in the tree hash either. A package is its
text.
