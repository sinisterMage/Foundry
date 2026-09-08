// Whether this registry is one.
//
// **Written in W#, against the same reader the client uses.** `ingot/registry`
// is a library module, so this program imports the very code `ingot resolve`
// runs -- which means there is no second implementation of the index format to
// keep in step with the first. A validator that parsed the TOML itself would
// be a description of the format that could drift from the definition, and the
// day it drifted the registry would pass its own check and break everybody.
//
// Two halves, because they cost different amounts:
//
//   * **Structural**, over every package, every run. Names, ordering, and
//     whether each requirement names something this registry holds. No network.
//   * **Fetched**, over the packages a pull request touched, which are named on
//     the command line. Each release is fetched at its recorded revision and
//     hashed, and the tree it comes to has to be the one the registry promised.
//     That is the check the whole scheme rests on: a registry that records a
//     hash it never verified is a registry that records a hope.
//
// Run from the root of a registry:
//
// ```sh
// wsharp run ci/check.ws                                   # structural only
// wsharp run ci/check.ws -- packages/acme/json/versions.toml   # and fetch that
// ```
const array = @import("std/array");
const fault = @import("ingot/fault");
const git = @import("ingot/git");
const io = @import("std/io");
const list = @import("std/list");
const manifest = @import("ingot/manifest");
const os = @import("std/os");
const path = @import("std/path");
const registry = @import("ingot/registry");
const semver = @import("ingot/semver");
const store = @import("ingot/store");
const text = @import("std/str");
const tls = @import("std/tls");
const x509 = @import("std/x509");

fn main() i64 {
    const f = fault.none();
    const ix = registry.open(f, ".") orelse {
        print(text.concat("error\t", f.message));
        return 1;
    };
    print(row2("registry", ix.name));

    var bad = 0;
    var checked = 0;
    for (registry.names(ix)) |name| {
        bad += check_package(ix, name);
        checked += 1;
    }
    print(row2("checked", text.from_int(checked)));

    // What a pull request touched is fetched as well. Every release of such a
    // package rather than only the new one: a published version is never
    // edited, so re-checking the old ones is redundant rather than wrong, and
    // it costs one fetch per version of one package.
    for (touched(os.args())) |name| { bad += verify_package(ix, name); }

    if (bad > 0) {
        print(row2("failed", text.from_int(bad)));
        return 1;
    }
    print("ok");
    return 0;
}

// ---------------------------------------------------------------------------
// Structural
// ---------------------------------------------------------------------------

/// Everything about a package that can be known without fetching it.
///
/// `registry.package` has already checked the things the *reader* must not go
/// on without -- that the name matches the path, the `repo` is `https://`, each
/// version parses, each `rev` is a full object id, each `tree` is a store key,
/// and no version is written twice. What is left is what only a whole registry
/// can answer.
fn check_package(ix: registry.Index, name: str) i64 {
    if (!registry.valid_name(name)) {
        return complain(name, "is not a name a registry may hold: two lowercase segments, `owner/name`");
    }
    const f = fault.none();
    const p = registry.package(f, ix, name) orelse {
        if (f.ok) { return complain(name, "has no readable package.toml"); }
        return complain(name, f.message);
    };

    var bad = 0;
    var last = semver.zero();
    var first = true;
    for (list.to_array(p.releases)) |r| {
        // Ascending, so that adding a release is one line at the end of a file
        // rather than an edit in the middle of one -- which is what makes the
        // "a published version is never edited" rule reviewable in a diff.
        if (!first and !semver.less(last, r.version)) {
            bad += complain(name, text.concat(semver.render(r.version),
                " is out of order: versions ascend"));
        }
        last = r.version;
        first = false;

        for (list.to_array(r.needs)) |need| {
            const g = fault.none();
            const there = registry.package(g, ix, need.package);
            if (there) |q| {
            } else {
                // Caught here rather than at resolve time, where it would be
                // "`acme/http` is not in Foundry" said to somebody who depends
                // on this package and did nothing wrong.
                if (!g.ok) { bad += complain(name, g.message); }
                bad += complain(name, text.concat(text.concat(semver.render(r.version),
                    " depends on "), text.concat(need.package, ", which is not in this registry")));
            }
        }
    }
    return bad;
}

// ---------------------------------------------------------------------------
// Fetched
// ---------------------------------------------------------------------------

fn verify_package(ix: registry.Index, name: str) i64 {
    const f = fault.none();
    const p = registry.package(f, ix, name) orelse {
        if (f.ok) { return complain(name, "was changed and is not in this registry"); }
        return complain(name, f.message);
    };
    const cfg = trust() orelse {
        return complain(name, "cannot be fetched: this machine has no certificate store");
    };
    const home = store.home() catch {
        return complain(name, "cannot be fetched: there is nowhere to put it");
    };
    var bad = 0;
    for (list.to_array(p.releases)) |r| { bad += verify_release(home, cfg, p, r); }
    return bad;
}

/// One release, fetched at its revision and held to what the registry says.
fn verify_release(home: str, cfg: tls.Config, p: registry.Package, r: registry.Release) i64 {
    const f = fault.none();
    const spelled = semver.render(r.version);
    const what = text.concat(p.name, text.concat(" ", spelled));

    const remote = git.Remote{ .url = p.repo, .cfg = cfg };
    const pack = git.fetch(f, remote, r.rev) orelse { return complain(what, f.message); };
    const files = git.files(f, pack, r.rev) orelse { return complain(what, f.message); };
    var carried: list.List[store.File] = list.new();
    for (list.to_array(files)) |file| {
        list.push(carried, store.File{ .path = file.path, .data = file.data });
    }
    const digest = store.install_files(f, home, carried);
    if (!f.ok) { return complain(what, f.message); }

    // The registry promised a hash. This is the line that makes it a promise:
    // everything downstream trusts the tree rather than the host, and it is
    // allowed to only because this ran.
    const got = text.concat("sha256:", digest);
    if (!text.eq(got, r.tree)) {
        return complain(what, text.concat(text.concat("hashes to ", got),
            text.concat(", and the registry says ", r.tree)));
    }

    const entry = store.entry(home, digest);
    const m = manifest.read(f, path.join(entry, manifest.MANIFEST_NAME)) orelse {
        return complain(what, "has no readable ingot.toml at that revision");
    };
    var bad = 0;
    if (!text.eq(m.name, p.name)) {
        bad += complain(what, text.concat("calls itself ", m.name));
    }
    if (!text.eq(m.version, spelled)) {
        bad += complain(what, text.concat("calls itself version ", m.version));
    }
    // A package presents exactly one file, and a package whose `root` is not
    // there installs and then cannot be imported -- which is a failure in
    // somebody else's build rather than in this pull request.
    if (!io.exists(path.join(entry, m.root))) {
        bad += complain(what, text.concat("has no ", m.root));
    }
    if (bad == 0) { print(row2("verified", what)); }
    return bad;
}

fn trust() ?tls.Config {
    const roots = x509.system_roots() catch return null;
    return tls.roots_config("", roots);
}

// ---------------------------------------------------------------------------
// The command line
// ---------------------------------------------------------------------------

/// The package names a list of changed paths mentions.
///
/// The workflow hands over what `git diff --name-only` said, which is every
/// path a pull request touched and not only the ones under `packages/`.
fn touched(args: []str) []str {
    var out = []str{};
    for (args) |arg| {
        const parts = text.split(path.normalise(arg), "/");
        if (array.len(parts) < 4) { continue; }
        if (!text.eq(parts[0], "packages")) { continue; }
        const name = text.concat(parts[1], text.concat("/", parts[2]));
        if (holds(out, name)) { continue; }
        out = array.push(out, name);
    }
    return out;
}

fn holds(l: []str, want: str) bool {
    for (l) |v| {
        if (text.eq(v, want)) { return true; }
    }
    return false;
}

/// One problem, on stdout with everything else, tab-separated the way every
/// answer in this toolchain is.
fn complain(name: str, what: str) i64 {
    print(row3("bad", name, what));
    return 1;
}

fn row2(a: str, b: str) str { return text.concat(a, text.concat("\t", b)); }
fn row3(a: str, b: str, c: str) str { return row2(a, row2(b, c)); }
