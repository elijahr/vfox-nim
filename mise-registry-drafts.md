# Drafts: getting `nim` into the mise registry

Post the discussion first, then paste its link into the mise-nim issue.

---

## 1. Discussion — github.com/jdx/mise/discussions (category: Ideas)

**Title:** Add `nim` to the registry via a native vfox plugin (`vfox-nim`)

I'd like to propose adding `nim` to the registry. I maintain [`vfox-nim`](https://github.com/elijahr/vfox-nim), a native vfox plugin for installing and managing Nim versions. It works with both mise and vfox, has 3-OS CI and integration tests, and is on tagged releases. It already works today via `mise use vfox:elijahr/vfox-nim@<version>`, just with the untrusted-plugin prompt.

I know the preference is aqua/github and that new asdf/vfox plugins generally aren't accepted. I think Nim is one of the cases the docs carve out for the plugin exception, since aqua/github can't really serve it:

- Nim ships official binaries only for Linux x64/x32 and Windows x64/x32. macOS and Linux ARM have none.
- The official stable binaries live on `nim-lang.org/download`, not GitHub releases, so aqua/ubi can't fetch them as release assets.
- The nightly builds (`nim-lang/nightlies`) do carry macOS/ARM assets, but only under rolling `latest-<branch>` tags. The per-version tags have no assets, so you can't pin a specific version through aqua.

So the plugin is doing real resolution work: official binary where available, else an exact-version nightly, else a generic nightly, else a source build, plus `ref:devel`/branch installs and `.nim-version`. I don't think aqua can template that.

For context, the existing `mise-plugins/mise-nim` is a fork of `asdf-community/asdf-nim` (the README is still asdf-nim's), runs through the asdf-bash shim, and hasn't been updated in about a year, so it isn't really a maintained option.

I'm happy to transfer `vfox-nim` into `mise-plugins` if that's the path, and I understand that means PRs reviewed by the owners rather than direct commits. Mostly I wanted to check whether this is something you'd consider before going further.

Thanks!

---

## 2. Issue — github.com/mise-plugins/mise-nim/issues

**Title:** `nim` has a maintained native vfox plugin now (`vfox-nim`)

Heads up for anyone landing here: this plugin is a fork of `asdf-community/asdf-nim` (the README is still asdf-nim's) and hasn't been updated in about a year.

There's a maintained native vfox plugin now, [`vfox-nim`](https://github.com/elijahr/vfox-nim), which works with both mise and vfox. You can use it today with `mise use vfox:elijahr/vfox-nim@<version>`.

I've opened a discussion about getting `nim` into the registry: <paste discussion link>

Thanks!
