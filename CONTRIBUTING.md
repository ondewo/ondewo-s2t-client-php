# How to become a contributor and submit your own code

## Contributor License Agreements

We'd love to accept your sample apps and patches! Before we can take them, we have to jump a couple of legal
hurdles.

Please fill out either the individual or corporate Contributor License Agreement (CLA).

* If you are an individual writing original source code and you're sure you own the intellectual property,
  then you'll need to sign an individual CLA.
* If you work for a company that wants to allow you to contribute your work, then you'll need to sign a
  corporate CLA.

Contact <office@ondewo.com> to receive the appropriate CLA and instructions for how to sign and return it.
Once we receive it, we'll be able to accept your pull requests.

## Contributing a patch

1. Submit an issue describing your proposed change to this repository.
1. The repository owner will respond to your issue promptly.
1. If your proposed change is accepted, and you haven't already done so, sign a Contributor License Agreement
   (see above).
1. Fork this repository, develop and test your code changes.
1. Ensure that your code adheres to the existing style.
1. Ensure that your code has an appropriate set of unit tests which all pass.
1. Submit a pull request.

## Getting set up

```bash
git clone --recurse-submodules git@github.com:ondewo/ondewo-s2t-client-php.git
cd ondewo-s2t-client-php
make setup_developer_environment_locally
```

That installs the submodules, resolves the composer dependencies and installs the pre-commit hooks. It, the
native `make test` / `make ci` and every other target that calls `php` or `composer` directly need PHP >= 8.1
with `ext-grpc` and Composer 2.x. The docker targets need only make, git, docker, perl and curl: `make build`
regenerates the stubs in the compiler image, and `make test_via_docker` runs the test suite in the utils image
built from `Dockerfile.utils`.

## What is generated and what is not

This is the single thing to internalise before touching the repository:

| Path | Owner | Committed? |
| --- | --- | --- |
| `src/` | the compiler image | yes — Packagist serves the tagged tree verbatim |
| `composer.json` | you, but **merged** by the compiler on every run | yes |
| `composer.lock`, `vendor/` | composer | no — gitignored |
| `auth/` | you | yes |
| `tests/`, `tools/` | you | yes |
| `ondewo-s2t-api`, `ondewo-proto-compiler` | their own repositories | as submodule commits |

* `src/` is deleted and rewritten on every `make generate_ondewo_protos`. **Never** put hand-written PHP
  there — put it in `auth/` at the repository root, which `composer.json` autoloads through `autoload.psr-4`.
* `composer.json` is merged with the image's default manifest (`require` = image defaults first, your
  constraints second; `autoload.classmap` always gains `src/`). Every other key you write survives untouched.
* Do **not** pin `google/protobuf` or `grpc/grpc` in `require`. The image resolves the library offline from a
  cache it pre-warmed at image-build time, so a pin outside that cache fails the generation run — loudly, by
  design, rather than silently rewriting your dependency.

## Changing the API surface

The stubs are a pure function of two submodule commits. To track a new API version:

1. Bump `ONDEWO_S2T_API_GIT_BRANCH` (and, for a new compiler release,
   `ONDEWO_PROTO_COMPILER_GIT_BRANCH`) at the top of the `Makefile`.
2. Run `make build`. It checks out the pins, rebuilds the compiler image from the submodule and regenerates the
   stubs. The compiler container runs as your user, so nothing it writes is root-owned.
3. Run `make test` (or `make test_via_docker`) and commit `src/`, the submodule pointers and the `Makefile`
   together — a regenerated `src/` that does not match the recorded submodule commits is not reproducible.

## Before you open a pull request

```bash
make precommit_hooks_run_all_files
make test              # or `make test_via_docker` without a local PHP
```

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat: …`, `fix(scope): …`,
`docs: …`). Do **not** prepend the JIRA ticket yourself — the `giticket` pre-commit hook reads it from the
branch name (`feature/OND211-1234-short-description`, or a bare `OND211-1234-…`) and prepends `[OND211-1234]`
for you. Writing it by hand produces a duplicated prefix.

## Releasing

Releases are cut by `make ondewo_release` on the releasing machine, never by CI — GitHub Actions only runs the
tests, and no credential is stored in GitHub. Normally ondewo-s2t-api's `make release_all_clients` runs it for
you. To run it yourself: bump `ONDEWO_S2T_VERSION` (it must match the ONDEWO S2T API in major and minor version)
and `ONDEWO_S2T_API_GIT_BRANCH`, add a `RELEASE.md` entry under a
`## Release ONDEWO S2T PHP Client <version>` heading followed by the `*****` separator the release notes are
sliced on, then run `make ondewo_release`. It writes the version into `composer.json` and the README itself,
takes the credentials from the `ondewo-devops-accounts` repository, checks that they are set and that the
GitHub token may push before anything is pushed, and ends with the Packagist ping and the GitHub release. The
release host needs only make, git, docker, perl and curl, because PHP, Composer and `gh` run in the utils
image. See the release section of the [README](README.md).
