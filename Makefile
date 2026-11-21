export

# =====================================================================================
# ondewo-s2t-client-php - Makefile
#
# The ONDEWO S2T (Speech-to-Text) gRPC client for PHP. The transport surface is
# generated from the .proto definitions of ondewo-s2t-api by the ondewo-proto-compiler's
# `ondewo-php-proto-compiler` image into src/ (committed - see .gitignore), the only hand-written
# code is the bearer-token auth surface in auth/, and the repository root IS the composer package
# that gets published.
#
# Quick start:
#   make help                    # list every documented target
#   make makefile_chapters       # list the section headers below
#   make update_submodules       # fetch ondewo-s2t-api + ondewo-proto-compiler
#   make build                   # submodules -> compiler image -> stubs -> version bump
#   make test                    # manifest validation + php -l + stub inventory + PHPUnit
#   make test_via_docker         # the same in the utils image (Dockerfile.utils) - no host php/composer
#   make ci                      # the checks of ci.yml's php job (no submodules, installs not included)
#   make ondewo_release          # the WHOLE release, locally - CI never builds, publishes or releases
#
# Host requirements: `make build`, `make test_via_docker` and `make ondewo_release` need only make,
# git, docker, perl and curl - php, composer and gh run in the utils image. The un-suffixed targets
# (test, packagist_dry_run, publish, push_to_gh, validate_release_credentials) are what runs INSIDE
# that image; ci.yml runs only the test/lint ones natively.
#
# Versioning: ONDEWO_S2T_VERSION (below) is the single source of truth and MUST
# match the ONDEWO S2T API in major and minor version. `make update_composer_version`
# propagates it into composer.json - never edit that field by hand.
#
# Overriding variables: pass on the command line, e.g. `make build PROTO_COMPILER_IMAGE=...`.
# Credentials (GITHUB_GH_TOKEN, PACKAGIST_USERNAME, PACKAGIST_API_TOKEN) live ONLY in the
# ondewo-devops-accounts repository: `make ondewo_release` clones it and hands them to `make release`
# at runtime. They are never committed here and never stored in GitHub.
# =====================================================================================

# ---------------- BEFORE RELEASE ----------------
# 1 - Update Version Number and API pin (ONDEWO_S2T_VERSION, ONDEWO_S2T_API_GIT_BRANCH below)
# 2 - Update RELEASE.md
# (ondewo-s2t-api's `make release_all_clients` does both and then runs `make ondewo_release`)
# -------------- Release Process Steps (`make ondewo_release`, all local) --------------
# 1 - Write the version into composer.json and README.md, check branch and tag are still free (spc)
# 2 - Get Credentials from devops-accounts repo
# 3 - Check the credentials are set, and that the GitHub token can push to this repository
# 4 - Build, then test and Packagist dry run in the utils image
# 5 - Commit, push, create Release Branch and Release Tag and push them
# 6 - Packagist Release (`make publish`: there is no upload step - Packagist serves the git tag,
#     so the release only validates the package and pings the update API to have it crawled)
# 7 - GitHub Release, LAST - so an existing GitHub release marks a complete release

########################################################
# 		Variables
########################################################

# MUST BE THE SAME AS THE API in Major and Minor Version Number
# example: API 2.9.0 --> Client 2.9.X
ONDEWO_S2T_VERSION=7.6.2

# Submodule pins. Both are checked out by `make checkout_defined_submodule_versions`, so the
# stubs of a release are always reproducible from the two commits recorded here.
ONDEWO_S2T_API_GIT_BRANCH=tags/7.6.0
# The compiler has to be 5.15.2 or newer: an older image adds "auth/" to composer.json's
# autoload.classmap and then aborts its own next run on it ('Could not scan for classes inside "auth/"').
ONDEWO_PROTO_COMPILER_GIT_BRANCH=tags/5.17.0

# Submodule directories - both sit at the repository root, see .gitmodules
ONDEWO_S2T_API_DIR=ondewo-s2t-api
ONDEWO_PROTO_COMPILER_DIR=ondewo-proto-compiler

# The FIXED image tag is the only contract with the proto compiler: `make build_compiler`
# rebuilds this very tag from the submodule, and `make generate_ondewo_protos` runs it.
PROTO_COMPILER_IMAGE=ondewo-php-proto-compiler:latest

# Everything that needs php, composer or gh runs in this image, built from Dockerfile.utils - the
# same scheme as the other ONDEWO clients' utils images.
IMAGE_UTILS_NAME=ondewo-s2t-client-utils-php:${ONDEWO_S2T_VERSION}
# The prefix of every utils-image run, followed by extra `-e NAME` flags and ${IMAGE_UTILS_NAME}.
# The repository is MOUNTED rather than COPYed, so what a target writes (vendor/, build/,
# tools/vendor/) lands in the working tree; --user keeps it owned by the invoking user, which is why
# HOME and composer's home and cache are pointed at a path that user can write.
UTILS_DOCKER_RUN=docker run --rm \
	--user "$$(id -u):$$(id -g)" \
	-e HOME=/tmp/home \
	-e COMPOSER_HOME=/tmp/home/.composer \
	-e COMPOSER_CACHE_DIR=/tmp/home/.composer/cache \
	-v "${CURDIR}":/home/ondewo \
	-w /home/ondewo

# Positional arguments of the compiler image's entrypoint:
#   <relative_protos_dir>  protoc's -I root INSIDE the input volume -> the api submodule
#   <target_subdir>        sub-directory of that root to scope generation to. `ondewo` keeps
#                          the vendored google/ tree out of the ENTRY set, while the image's
#                          dependency resolver still pulls in the google protos that are
#                          actually imported (google/api/annotations.proto, ...).
PROTOS_TARGET_SUBDIR=ondewo

# The dev tool chain (PHPUnit + the coverage gate) lives in its OWN composer project under tools/,
# never in the root manifest's require-dev - see tools/README.md: `composer update --no-dev` still
# RESOLVES require-dev, and the compiler image resolves the merged manifest with the network off,
# so one require-dev entry in composer.json takes `make generate_ondewo_protos` down with it.
TOOLS_DIR=tools
PHPUNIT=${TOOLS_DIR}/vendor/bin/phpunit
COVERAGE_CHECK=${TOOLS_DIR}/vendor/bin/coverage-check
CLOVER_REPORT=build/coverage/clover.xml
# The hand-written sources. MUST stay in sync with phpunit.xml.dist's <source><include>.
COVERAGE_SOURCE_DIR=auth
# Minimum coverage of the HAND-WRITTEN sources. The generated stubs are machine output and are
# excluded from the metric - they are exercised instead by tests/Generated/*, which loads every
# generated class and initialises every proto descriptor.
COVERAGE_MIN=100
# pcov AUTO-DETECTS pcov.directory and picks this repository's src/ - the generated tree - which
# makes it instrument nothing that phpunit.xml.dist's <source> covers and report a flat 0%. The
# directive is PHP_INI_SYSTEM, so phpunit.xml.dist's <ini> cannot set it; it has to be passed on
# the interpreter's command line. Harmless when the driver is xdebug (unknown directive, ignored).
PHP_COVERAGE_FLAGS=-d pcov.enabled=1 -d pcov.directory=${COVERAGE_SOURCE_DIR}

# Supplied at runtime by run_release_with_devops from ondewo-devops-accounts (account_github.env).
# It needs push access to this repository, which `release` checks before its first push.
GITHUB_GH_TOKEN?=ENTER_YOUR_TOKEN_HERE

# Terminate on the ***** separator that delimits release entries, NOT on /\*\*/ - that matched the
# first markdown **bold** span inside the entry and silently truncated the notes there, with no
# error from `gh release create`. Same fix as ondewo-s2t-api's and ondewo-s2t-client-python's Makefile.
CURRENT_RELEASE_NOTES=`cat RELEASE.md \
	| perl -ne 'print if /Release ONDEWO S2T PHP Client ${ONDEWO_S2T_VERSION}/../^\*{5}/'`

GH_REPO="https://github.com/ondewo/ondewo-s2t-client-php"
# The same repository as GitHub's REST API path, for the token check in validate_release_credentials.
GH_API_REPO=repos/ondewo/ondewo-s2t-client-php
DEVOPS_ACCOUNT_GIT="ondewo-devops-accounts"
DEVOPS_ACCOUNT_DIR="./${DEVOPS_ACCOUNT_GIT}"

# ---------------- PACKAGIST ----------------
# Packagist has NO upload endpoint. It serves the tree of a git TAG of this very repository, so
# "publishing" is the tag that `make create_release_tag` already pushes plus a ping that tells
# Packagist to crawl it - `make publish`. The package was submitted to Packagist once, before 7.1.0
# (the update API answers 404 for a package it does not know); no release step is manual.
# Credentials: the Packagist login name and the token from https://packagist.org/profile/
# ("Show API token"). Both are read at runtime from the ondewo-devops-accounts repo
# (account_packagist.env) - never committed, never stored in GitHub.
PACKAGIST_USERNAME?=ENTER_HERE_YOUR_PACKAGIST_USERNAME
PACKAGIST_API_TOKEN?=ENTER_HERE_YOUR_PACKAGIST_API_TOKEN
PACKAGIST_PACKAGE=ondewo/s2t-client-php
PACKAGIST_UPDATE_API=https://packagist.org/api/update-package
# GH_REPO carries its double quotes as part of the VALUE (harmless in a recipe, where the shell
# strips them again); the JSON payload below is assembled by make itself, so they come off here.
PACKAGIST_REPOSITORY_URL=$(subst ",,$(GH_REPO))
# The request body of the update API. It carries no credentials - those travel in an
# Authorization header - which is why `make packagist_dry_run` can verify the exact payload the
# real publish sends without holding a single secret.
PACKAGIST_UPDATE_PAYLOAD={"repository":{"url":"$(PACKAGIST_REPOSITORY_URL)"}}

# The release tag under verification. Left EMPTY on an ordinary checkout, where
# `check_version_agreement` derives it from HEAD instead (and finds none on a branch); `release` sets
# it to the tag it is about to create, so the tag/version agreement can never be skipped there.
RELEASE_TAG?=

# `make` with no target prints the help listing.
.DEFAULT_GOAL := help

# Define colors globally (reused for [INFO]/[SUCCESS]/[ERROR] log lines in recipes)
BLUE   := \033[1;34m
GREEN  := \033[0;32m
RED    := \033[0;31m
NC     := \033[0m

########################################################
#       ONDEWO Standard Make Targets
########################################################

setup_developer_environment_locally: update_submodules install_dependencies install_dev_tools install_precommit_hooks ## Ready a fresh laptop: submodules, composer dependencies, dev tools and pre-commit hooks

install_precommit_hooks: ## Installs pre-commit hooks and sets them up for the ondewo-s2t-client-php repo
	pre-commit install
	pre-commit install --hook-type commit-msg

precommit_hooks_run_all_files: ## Runs all pre-commit hooks on all files and not just the changed ones
	pre-commit run --all-files

help: ## Print usage info about help targets
	# (first comment after target starting with double hashes ##)
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-40s\033[0m %s\n", $$1, $$2}'

makefile_chapters: ## Shows all sections of Makefile
	@echo `cat Makefile| grep "########################################################" -A 1 | grep -v "########################################################"`

TEST: ## Prints some important variables
	@echo "Client Version: \t ${ONDEWO_S2T_VERSION}"
	@echo "API Pin: \t\t ${ONDEWO_S2T_API_GIT_BRANCH}"
	@echo "Compiler Pin: \t\t ${ONDEWO_PROTO_COMPILER_GIT_BRANCH}"
	@echo "Compiler Image: \t ${PROTO_COMPILER_IMAGE}"
	@echo "GH Token: \t\t $(if $(filter-out ENTER_YOUR_TOKEN_HERE,$(GITHUB_GH_TOKEN)),<set>,<unset>)"
	@echo "Packagist Package: \t ${PACKAGIST_PACKAGE}"
	@echo "Packagist User: \t $(if $(filter-out ENTER_HERE_YOUR_PACKAGIST_USERNAME,$(PACKAGIST_USERNAME)),<set>,<unset>)"
	@echo "Packagist Token: \t $(if $(filter-out ENTER_HERE_YOUR_PACKAGIST_API_TOKEN,$(PACKAGIST_API_TOKEN)),<set>,<unset>)"
	@echo "Release Notes: \n \n$(CURRENT_RELEASE_NOTES)"

########################################################
#       Repo Specific Make Targets
########################################################
#		Build

build: checkout_defined_submodule_versions build_compiler generate_ondewo_protos update_composer_version update_readme_version ## Build the client: submodules -> compiler image -> stubs -> version bump
	@echo "$(GREEN)[SUCCESS]$(NC) ondewo-s2t-client-php ${ONDEWO_S2T_VERSION} built"

build_compiler: ## Build the ondewo-php-proto-compiler docker image from the submodule
	@echo "$(BLUE)[INFO]$(NC) Building ${PROTO_COMPILER_IMAGE} from ${ONDEWO_PROTO_COMPILER_DIR}/php ..."
# The image COPYs php/image-data with the mode bits of this checkout, and generate_ondewo_protos runs
# it as a non-root user. A checkout made under a restrictive umask (077, e.g. while capturing a
# release log) would land root-owned 0600 in the image: "compile-proto-2-php.sh: Permission denied".
# a+rX adds only read (and x where some x is already set), which git does not track.
	chmod -R a+rX ${ONDEWO_PROTO_COMPILER_DIR}/php
	cd ${ONDEWO_PROTO_COMPILER_DIR}/php && sh build.sh
	@echo "$(GREEN)[SUCCESS]$(NC) ${PROTO_COMPILER_IMAGE} built"

# NOTE: no `-it`. It breaks every non-interactive caller (CI, `make release`) with
#	"cannot attach stdin to a TTY-enabled container because stdin is not a terminal".
#	-it belongs only on the `--entrypoint /bin/bash` debug command documented in the README.
# NOTE: input volume AND output volume are both the repository root. The image copies the input
#	volume into an internal temp directory and compiles there, so the mounted input is never
#	mutated; it then writes composer.json, composer.lock, src/ and vendor/ back here, wiping its
#	own src/ and vendor/ first so a renamed or deleted proto leaves no orphaned stub behind.
#	The repository root has to be the input volume because the image reads BOTH the proto root
#	(${ONDEWO_S2T_API_DIR}) and this package's composer.json from there - it merges
#	that manifest with its own defaults instead of overwriting it.
# NOTE: hand-written PHP belongs in auth/ at the repository root, NEVER in src/. src/ is
#	compiler-owned and wiped on every run; composer.json's autoload.psr-4 maps auth/.
# NOTE: the container runs as the invoking user (--user), so src/, vendor/ and composer.* come out
#	owned by you and no sudo chown is needed afterwards. The image was built to run as root, so its
#	root-owned paths are redirected; the first and the last are load-bearing (verified against compiler
#	5.15.1, which fails without either), HOME and COMPOSER_HOME only keep composer off root-owned homes:
#	TEMP_SRC_DIRECTORY   its staging directory, by default /image-data/src ("Permission denied");
#	COMPOSER_HOME        by default /image-data/composer-home;
#	COMPOSER_CACHE_READ_ONLY=1  the offline resolution reads the root-owned, pre-warmed
#	                     /image-data/composer-cache; without the flag composer finds that cache
#	                     unwritable, "proceeds without cache" and fails on the disabled network.
generate_ondewo_protos: ## Generate the PHP gRPC client stubs from the .proto definitions into src/
	@test -d ${ONDEWO_S2T_API_DIR}/${PROTOS_TARGET_SUBDIR} \
		|| { echo "$(RED)[ERROR]$(NC) '${ONDEWO_S2T_API_DIR}/${PROTOS_TARGET_SUBDIR}' not found - run 'make update_submodules' first"; exit 1; }
	@echo "$(BLUE)[INFO]$(NC) Generating PHP stubs from ${ONDEWO_S2T_API_DIR}/${PROTOS_TARGET_SUBDIR} ..."
	docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e HOME=/tmp/home \
		-e TEMP_SRC_DIRECTORY=/tmp/compile-src \
		-e COMPOSER_HOME=/tmp/home/.composer \
		-e COMPOSER_CACHE_READ_ONLY=1 \
		-v ${shell pwd}:/input-volume \
		-v ${shell pwd}:/output-volume \
		${PROTO_COMPILER_IMAGE} ${ONDEWO_S2T_API_DIR} ${PROTOS_TARGET_SUBDIR}
	@echo "$(GREEN)[SUCCESS]$(NC) PHP stubs generated in src/"

update_composer_version: ## Set ONDEWO_S2T_VERSION as the `version` field of composer.json
	@perl -i -pe 's/^(\s*"version":\s*")[0-9]+\.[0-9]+\.[0-9]+(")/$${1}${ONDEWO_S2T_VERSION}$${2}/' composer.json
	@echo "$(GREEN)[SUCCESS]$(NC) composer.json version set to ${ONDEWO_S2T_VERSION}"

# The README's `composer require ondewo/s2t-client-php:^X.Y` and `"ondewo/s2t-client-php": "^X.Y"`
# snippets name the minor series of ONDEWO_S2T_VERSION, and its repository tree names the compiler
# pin. ondewo-s2t-api's release_client rewrites only this Makefile's version and pin lines, so without
# this the published README would keep recommending the previous minor and citing the previous compiler.
README_MINOR_SERIES=$(word 1,$(subst ., ,${ONDEWO_S2T_VERSION})).$(word 2,$(subst ., ,${ONDEWO_S2T_VERSION}))
update_readme_version: ## Set the README's install snippets to the minor series of ONDEWO_S2T_VERSION and its tree to the compiler pin
	@perl -i -pe 's/(ondewo\/s2t-client-php(?::|":\s*")\^)\d+\.\d+/$${1}${README_MINOR_SERIES}/g' README.md
	@perl -i -pe 's{(submodule: the compiler images, pinned to )\S+}{$${1}${ONDEWO_PROTO_COMPILER_GIT_BRANCH}}' README.md
	@echo "$(GREEN)[SUCCESS]$(NC) README.md install snippets set to ^${README_MINOR_SERIES}, compiler pin to ${ONDEWO_PROTO_COMPILER_GIT_BRANCH}"

install_dependencies: ## Resolve and install the composer dependencies of the package (needs network)
# composer.json's autoload.classmap lists "src/", and `composer update` aborts with
#	'Could not scan for classes inside "src/" which does not appear to be a file nor a folder'
#	when the stubs have not been generated yet. An empty src/ is harmless - it is compiler-owned
#	and wiped on the next generation run, and git does not track empty directories.
	@mkdir -p src
	composer update --prefer-dist --no-interaction --no-progress

install_dev_tools: ## Resolve and install PHPUnit + the coverage gate into tools/vendor (needs network)
# No lock file is committed for tools/: it would pin ONE phpunit major, and this repository is
#	tested on php 8.2 through 8.4 - the constraint has to be re-resolved
#	per interpreter, which is what `update` does and `install` cannot.
	composer update --working-dir=${TOOLS_DIR} --prefer-dist --no-interaction --no-progress

clean: ## Remove the composer artifacts, the dev tools and the generated stubs
	rm -rf vendor composer.lock src ${TOOLS_DIR}/vendor ${TOOLS_DIR}/composer.lock build .phpunit.cache

########################################################
#		Test

test: composer_validate packagist_dry_run lint_php check_build coverage ## Validate the manifest, verify the packaging path, syntax-check hand-written PHP, check the stubs against the api submodule and run the covered PHPUnit suite

# The checks .github/workflows/ci.yml's php job runs after its install_dependencies and
# install_dev_tools steps (which `coverage` needs, so run those two first on a fresh checkout) - a
# test and lint gate, nothing that packages or publishes (the Packagist dry run is part of `test`,
# which the local release runs). It deliberately leaves `check_build` out: that target compares src/
# against the ondewo-s2t-api submodule, and CI checks out NO submodules - the stubs are committed, so
# what CI has to prove is that the COMMITTED tree passes its tests. tests/Generated/GeneratedCodeTest.php
# carries the submodule-free half of the same assertion (every generated class loads, every descriptor
# initialises, every expected service client exists) and fails - never skips - when src/ is missing.
ci: composer_validate lint_php coverage ## Run the CI gate locally (no submodules, no docker)
	@echo "$(GREEN)[SUCCESS]$(NC) CI gate passed"

composer_validate: ## Validate composer.json
# Deliberately NOT --strict: the `version` field the release targets bump is a strict-mode
# warning that --strict turns into a failure (rc 1), exactly as in the compiler image.
# `composer_validate_strict` below runs --strict anyway, with the deliberate warnings enumerated,
# so a NEW warning still fails the build.
	composer validate --no-check-publish --no-interaction

lint_php: ## Syntax-check every hand-written PHP file with `php -l` (src/ is generated and skipped)
	@for dir in auth tests examples; do \
		[ -d "$$dir" ] || continue; \
		find "$$dir" -type f -name '*.php' | while IFS= read -r f; do \
			php -l "$$f" > /dev/null || { echo "$(RED)[ERROR]$(NC) php -l failed: $$f"; exit 1; }; \
		done || exit 1; \
	done
	@echo "$(GREEN)[SUCCESS]$(NC) hand-written PHP sources are syntactically valid"

check_build: ## Fails if any .proto of the API submodule has no generated PHP code
	@test -d src \
		|| { echo "$(RED)[ERROR]$(NC) src/ is missing - run 'make generate_ondewo_protos' first"; exit 1; }
	@test -d ${ONDEWO_S2T_API_DIR}/${PROTOS_TARGET_SUBDIR} \
		|| { echo "$(RED)[ERROR]$(NC) '${ONDEWO_S2T_API_DIR}/${PROTOS_TARGET_SUBDIR}' not found - run 'make update_submodules' first"; exit 1; }
# protoc's php generator names a file after the UpperCamel form of the .proto basename, split on
# '_' AND '-' (ai_services.proto -> AiServices.php, speech-to-text.proto -> SpeechToText.php), so
# the basename is camel-cased the same way before it is looked up.
	@find ${ONDEWO_S2T_API_DIR}/${PROTOS_TARGET_SUBDIR} -type f -name '*.proto' \
		| while IFS= read -r proto; do \
			camel=`basename "$$proto" .proto | awk -F'[_-]' '{s=""; for(i=1;i<=NF;i++){s = s toupper(substr($$i,1,1)) substr($$i,2)}; print s}'`; \
			find src -type f -name "$$camel.php" | grep -q . \
				|| { echo "$(RED)[ERROR]$(NC) No PHP code generated for $$proto (expected a $$camel.php)"; exit 1; }; \
		done || exit 1
	@echo "$(GREEN)[SUCCESS]$(NC) every .proto has generated PHP code"

# NOTE: no `[ -x ... ] || skip` guard. A missing tool chain or a missing test suite is a RED
#	build, not a green one - that guard is exactly what let this repository's CI pass while it
#	held no code at all.
phpunit: ## Run the PHPUnit suite
	@test -x ${PHPUNIT} \
		|| { echo "$(RED)[ERROR]$(NC) '${PHPUNIT}' is missing - run 'make install_dev_tools'"; exit 1; }
	@test -f vendor/autoload.php \
		|| { echo "$(RED)[ERROR]$(NC) 'vendor/autoload.php' is missing - run 'make install_dependencies'"; exit 1; }
	${PHPUNIT} --colors=never

coverage: ## Run the PHPUnit suite with coverage and fail below COVERAGE_MIN% of the hand-written code
	@test -x ${PHPUNIT} \
		|| { echo "$(RED)[ERROR]$(NC) '${PHPUNIT}' is missing - run 'make install_dev_tools'"; exit 1; }
	@test -f vendor/autoload.php \
		|| { echo "$(RED)[ERROR]$(NC) 'vendor/autoload.php' is missing - run 'make install_dependencies'"; exit 1; }
# --fail-on-skipped/--fail-on-incomplete: a test that quietly skips itself is the green-by-omission
#	failure mode this suite exists to rule out.
	php ${PHP_COVERAGE_FLAGS} ${PHPUNIT} --colors=never --fail-on-skipped --fail-on-incomplete \
		--coverage-clover ${CLOVER_REPORT} --coverage-text
	@test -f ${CLOVER_REPORT} \
		|| { echo "$(RED)[ERROR]$(NC) no coverage report at '${CLOVER_REPORT}' - is a coverage driver (pcov/xdebug) enabled?"; exit 1; }
	${COVERAGE_CHECK} ${CLOVER_REPORT} ${COVERAGE_MIN}

########################################################
#		Utils docker image

build_utils_docker_image: ## Build the utils docker image (php + ext-grpc/pcov/bcmath, composer, gh) from Dockerfile.utils
	docker build -f Dockerfile.utils -t ${IMAGE_UTILS_NAME} .

# `make test` needs vendor/ and tools/vendor/, which a fresh container does not have, so the two
# install targets run first. RELEASE_TAG is forwarded: `release` sets it, because at that point HEAD
# is still the previous commit - after a release that is the previous release's TAG, and
# check_version_agreement would otherwise compare that tag with the new ONDEWO_S2T_VERSION.
test_via_docker: build_utils_docker_image ## Run `make test` (dependencies, Packagist dry run, php -l, check_build, PHPUnit + coverage) in the utils image
	${UTILS_DOCKER_RUN} ${IMAGE_UTILS_NAME} make install_dependencies install_dev_tools test RELEASE_TAG=${RELEASE_TAG}

packagist_dry_run_via_docker: build_utils_docker_image ## Run the credential-free Packagist dry run in the utils image
	${UTILS_DOCKER_RUN} ${IMAGE_UTILS_NAME} make packagist_dry_run RELEASE_TAG=${RELEASE_TAG}

# validate_release_credentials in the utils image (the host has no gh). The token goes in by NAME, like
# release_to_github_via_docker_image below. Builds the image first: this runs before the first push.
validate_release_credentials_via_docker_image: build_utils_docker_image ## Check in the utils image that GitHub accepts GITHUB_GH_TOKEN and it can push to this repository
	@${UTILS_DOCKER_RUN} -e GITHUB_GH_TOKEN ${IMAGE_UTILS_NAME} make validate_release_credentials

########################################################
#		Submodules

update_submodules: ## Initialize and update all submodules
	@echo "$(BLUE)[INFO]$(NC) START initializing submodules ..."
	git submodule update --init --recursive
	@echo "$(GREEN)[SUCCESS]$(NC) DONE initializing submodules"

checkout_defined_submodule_versions: update_submodules ## Check out the submodule versions pinned at the top of this Makefile
	@echo "$(BLUE)[INFO]$(NC) START checking out submodules ..."
	git -C ${ONDEWO_S2T_API_DIR} fetch --all
	git -C ${ONDEWO_S2T_API_DIR} checkout ${ONDEWO_S2T_API_GIT_BRANCH}
	git -C ${ONDEWO_PROTO_COMPILER_DIR} fetch --all
	git -C ${ONDEWO_PROTO_COMPILER_DIR} checkout ${ONDEWO_PROTO_COMPILER_GIT_BRANCH}
	@echo "$(GREEN)[SUCCESS]$(NC) DONE checking out submodules"

########################################################
#		Release

release: ## Automate the entire release process (run through `make ondewo_release`, which supplies the credentials)
	@echo "$(BLUE)[INFO]$(NC) Start Release"
# FIRST, before anything is built, committed, branched, tagged or pushed. Both credentials used to
# be exercised only at the very END of this recipe - GITHUB_GH_TOKEN in login_to_gh, the Packagist
# pair in `make publish` - by which time the release branch and the release tag are already on
# origin. A missing token therefore left an immovable tag behind, and `spc` then refused every
# retry because that branch and that tag now exist. A release that cannot reach GitHub or
# Packagist has to fail while it is still a no-op.
	make check_release_credentials
# Same reasoning for the notes: `gh release create -n ""` publishes an EMPTY release without
# complaining, and that cannot be discovered after the tag has been pushed either.
	make check_release_notes
# Set is not the same as valid: the GitHub token logs gh in exactly as the GitHub release will, and is
# asked, read-only, whether it may push here (this builds the utils image first). The Packagist pair
# has no such check - Packagist documents no read-only endpoint that takes the token (its only
# authenticated calls are update, create and edit, all writes) - so a wrong Packagist token still
# surfaces only at the ping, after the tag. See README.
	make validate_release_credentials_via_docker_image
	make build
	-make precommit_hooks_run_all_files
	make check_build
# The test suite and the Packagist dry run (everything `publish` verifies except the credentials) run
# here, in the utils image, BEFORE the first push: from `git push` on, a failure leaves a pushed
# master, release branch and tag behind that `spc` refuses to release again. RELEASE_TAG is the tag
# this release is about to create - see test_via_docker.
	make test_via_docker RELEASE_TAG=${ONDEWO_S2T_VERSION}
	git status
	git add src
	git add composer.json
	git add Makefile
	git add README.md
	git add RELEASE.md
# auth/ is the hand-written surface (bearer credentials, Keycloak token provider). It is
# top-level and NOT covered by `git add src`, so leaving it out means a fix written there is
# published from the tag without ever reaching the repository.
	git add auth
# tests/ and tools/ are not part of the published classmap, but a regression test written alongside
# a fix must reach the repository or CI never runs it. Every path here exists, so no leading `-`:
# one missing pathspec makes git reject the WHOLE add, which the `-` used to hide.
	git add tests tools phpunit.xml.dist
	git add ${ONDEWO_PROTO_COMPILER_DIR}
	git add ${ONDEWO_S2T_API_DIR}
	git status
# Commit only when something is staged, but never ignore a FAILED commit (no git identity, a
# broken index): a `-` here would let the release tag and publish the previous commit.
	git diff --cached --quiet || git commit --no-verify -m "PREPARING FOR RELEASE ${ONDEWO_S2T_VERSION}"
	git push
	make create_release_branch
	make create_release_tag
# The PHP equivalent of `make push_to_pypi_via_docker` / `make publish_npm_via_docker`: nothing is
# uploaded, the tag pushed above IS the artifact, and this only tells Packagist to crawl it. It
# has to run AFTER create_release_tag - Packagist crawls what is on GitHub at that moment. Runs in
# the utils image that test_via_docker built above.
	make publish_via_docker_image RELEASE_TAG=${ONDEWO_S2T_VERSION}
# LAST, so that an existing GitHub release means every step before it succeeded. Utils image too -
# the host has no gh.
	make release_to_github_via_docker_image
	@echo "$(GREEN)[SUCCESS]$(NC) Release Finished - tag ${ONDEWO_S2T_VERSION} pushed, Packagist crawl of ${PACKAGIST_PACKAGE} requested, GitHub release created"

create_release_branch: ## Create Release Branch and push it to origin
	git checkout -b "release/${ONDEWO_S2T_VERSION}"
	git push -u origin "release/${ONDEWO_S2T_VERSION}"

create_release_tag: ## Create Release Tag and push it to origin
	git tag -a ${ONDEWO_S2T_VERSION} -m "release/${ONDEWO_S2T_VERSION}"
	git push origin ${ONDEWO_S2T_VERSION}

########################################################
#		GITHUB

push_to_gh: login_to_gh build_gh_release ## Logs into GitHub CLI and Releases
	@echo "$(GREEN)[SUCCESS]$(NC) Released to GitHub"

# The token is passed by NAME (`-e GITHUB_GH_TOKEN`): docker copies the value out of the environment
# (line 1 exports every variable), so it never appears on docker's command line. @ keeps it out of the
# log even if the flag is ever rewritten to `-e NAME=value`. Uses the image as built - `release` builds
# it before the first push, and nothing after the tag may fail on an image build.
release_to_github_via_docker_image: ## Release to GitHub from the utils image (gh auth login + gh release create)
	@${UTILS_DOCKER_RUN} -e GITHUB_GH_TOKEN ${IMAGE_UTILS_NAME} make push_to_gh

# Never prints the token, only whether it is usable. The EMPTY string has to be rejected next to
# the placeholder: a devops-accounts file without the line leaves the placeholder, an empty
# `GITHUB_GH_TOKEN=` line and `make release GITHUB_GH_TOKEN=` expand to the empty string, and
# `gh auth login --with-token` fed an empty line fails long after the tag has been pushed.
# Split out of login_to_gh so `release` can run it as its very first step - see the comment there.
check_gh_credentials: ## Fail unless GITHUB_GH_TOKEN is set
	@if [ -z "$${GITHUB_GH_TOKEN}" ] || [ "$${GITHUB_GH_TOKEN}" = "ENTER_YOUR_TOKEN_HERE" ]; then \
		echo "$(RED)[ERROR]$(NC) GITHUB_GH_TOKEN is not set - it comes from ondewo-devops-accounts (account_github.env) through 'make ondewo_release'"; exit 1; fi
	@echo "$(GREEN)[SUCCESS]$(NC) GITHUB_GH_TOKEN is set"

# The host-side presence check of every credential `release` uses - the first thing it runs.
check_release_credentials: check_gh_credentials check_packagist_credentials ## Fail unless GITHUB_GH_TOKEN, PACKAGIST_USERNAME and PACKAGIST_API_TOKEN are set

# Runs INSIDE the utils image (validate_release_credentials_via_docker_image), before anything is
# pushed. First login_to_gh, the very `gh auth login --with-token` the GitHub release runs last: it
# rejects a revoked or mistyped token (HTTP 401) and a classic token without the `repo` and `read:org`
# scopes gh requires, and it writes its config only into the throwaway container. Then, read-only,
# GET /repos/{owner}/{repo}, whose `permissions.push` says whether the token's user may push here; a
# valid token without write access prints false. @ keeps the value out of the log.
validate_release_credentials: login_to_gh ## Fail unless GitHub accepts GITHUB_GH_TOKEN and it may push to this repository
	@push=`GH_TOKEN="$${GITHUB_GH_TOKEN}" gh api ${GH_API_REPO} --jq .permissions.push` \
		|| { echo "$(RED)[ERROR]$(NC) could not read the permissions of GITHUB_GH_TOKEN on ${GH_API_REPO} (see gh's message above) - on HTTP 401 fix account_github.env in ondewo-devops-accounts"; exit 1; }; \
	if [ "$$push" != "true" ]; then \
		echo "$(RED)[ERROR]$(NC) GITHUB_GH_TOKEN is valid but has no push access to ${GH_API_REPO} (permissions.push=$$push)"; exit 1; fi
	@echo "$(GREEN)[SUCCESS]$(NC) GITHUB_GH_TOKEN is valid and may push to ${GH_API_REPO}"

# Prefixed with @ so the token never reaches the build log. Read as $${GITHUB_GH_TOKEN}, which the
# shell expands from the exported environment: make would expand $(GITHUB_GH_TOKEN) into the
# `sh -c` command line, and /proc/<pid>/cmdline is world-readable. printf is a shell builtin.
login_to_gh: check_gh_credentials ## Login to Github CLI with Access Token
	@printf '%s\n' "$${GITHUB_GH_TOKEN}" | gh auth login -p ssh --with-token

# `gh release create -n ""` succeeds and publishes an EMPTY release, so a forgotten RELEASE.md
# entry - or a heading whose wording drifted away from what the CURRENT_RELEASE_NOTES flip-flop
# greps for - is otherwise only noticed by whoever reads the release page afterwards. This asserts
# the SLICE, not the heading: check_version_agreement already greps for the heading, and only a
# non-empty slice proves the perl flip-flop actually produced notes to publish.
check_release_notes: ## Assert RELEASE.md carries an entry for ONDEWO_S2T_VERSION
	@notes="$(CURRENT_RELEASE_NOTES)"; \
	if [ -z "$$notes" ]; then \
		echo "$(RED)[ERROR]$(NC) RELEASE.md has no '## Release ONDEWO S2T PHP Client ${ONDEWO_S2T_VERSION}' entry"; \
		echo "        The GitHub release would be created with empty notes - add the entry first."; \
		exit 1; \
	fi; \
	echo "$(GREEN)[SUCCESS]$(NC) RELEASE.md has release notes for ${ONDEWO_S2T_VERSION}"

build_gh_release: check_release_notes ## Generate Github Release with CLI
	gh release create --repo $(GH_REPO) "$(ONDEWO_S2T_VERSION)" -n "$(CURRENT_RELEASE_NOTES)" -t "Release ${ONDEWO_S2T_VERSION}"

########################################################
#		PACKAGIST

# The equivalent of `twine upload` (python) or `npm publish` (typescript) - except that Packagist
# accepts no artifact at all. It reads the git tag straight off GitHub, so the only thing left to
# do is (1) prove the tagged tree is a publishable composer package and (2) ask Packagist to crawl
# it now instead of at its next scheduled pass.
# check_packagist_credentials runs FIRST so a missing token fails in a second rather than after
# the whole validation pass.
publish: check_packagist_credentials packagist_dry_run packagist_update ## Validate the package and tell Packagist to crawl the new tag (the PHP equivalent of an upload)
	@echo "$(GREEN)[SUCCESS]$(NC) Packagist crawl of ${PACKAGIST_PACKAGE} ${ONDEWO_S2T_VERSION} requested - it appears on https://packagist.org/packages/${PACKAGIST_PACKAGE} once Packagist has crawled the tag"

# `make publish` in the utils image, which has the php and composer the dry run needs. The
# credentials are passed by NAME, like release_to_github_via_docker_image. Uses the image as built.
publish_via_docker_image: ## Run `make publish` (dry run + Packagist update ping) in the utils image
	@${UTILS_DOCKER_RUN} -e PACKAGIST_USERNAME -e PACKAGIST_API_TOKEN ${IMAGE_UTILS_NAME} make publish RELEASE_TAG=${RELEASE_TAG}

# Everything `publish` can check WITHOUT a credential. Part of `make test`, which `release` runs in the
# utils image before the first push, so a packaging problem fails the release while it is still a no-op.
packagist_dry_run: composer_validate composer_validate_strict check_version_agreement check_packagist_payload ## Credential-free verification of the whole packaging path (part of `make test`)
	@echo "$(GREEN)[SUCCESS]$(NC) Packagist dry run passed - ${PACKAGIST_PACKAGE} ${ONDEWO_S2T_VERSION} is publishable"

# `composer validate --strict` reports exactly three warnings here, all of them deliberate and
# permanent:
#   * "The version field is present"        - composer.json's `version` is what
#     `make update_composer_version` writes and what `spc` (Test 3) refuses to release without.
#     Packagist derives the version from the TAG, but the fleet keeps the field so the version is
#     greppable in the tree; `check_version_agreement` below is what keeps the two from drifting.
#   * the two exact version constraints     - google/protobuf and grpc/grpc MUST be pinned to the
#     exact versions the compiler image ships (README rule 2): the image resolves the merged
#     manifest with the network OFF, from a cache warmed at image-build time, so a range that
#     resolves to anything else takes `make generate_ondewo_protos` down.
# So --strict can never be run bare here (it exits 1 on a warning). This target runs it anyway and
# fails on any warning that is NOT one of those three - a newly introduced warning is a real
# regression and would otherwise drown in `composer validate`'s output.
# --no-check-lock: composer.lock is deliberately NOT committed here (see .gitignore - this is a
# library, and the compiler image writes a --no-dev lock of its own). `make test_via_docker` validates
# after `make install_dependencies` has written one, and would otherwise fail on a purely local
# artifact that is never published.
composer_validate_strict: ## Run `composer validate --strict` and fail on any warning beyond the three deliberate ones
	@mkdir -p build
	@composer validate --strict --no-check-lock --no-ansi --no-interaction > build/composer-validate-strict.log 2>&1 || true
	@cat build/composer-validate-strict.log
	@grep -q "is valid" build/composer-validate-strict.log \
		|| { echo "$(RED)[ERROR]$(NC) composer.json is INVALID - see the output above"; exit 1; }
	@grep '^- ' build/composer-validate-strict.log \
		| grep -v -e "The version field is present" \
		          -e "require.google/protobuf : exact version constraints" \
		          -e "require.grpc/grpc : exact version constraints" \
		> build/composer-validate-strict.unexpected || true
	@if [ -s build/composer-validate-strict.unexpected ]; then \
		echo "$(RED)[ERROR]$(NC) composer validate --strict reported warnings beyond the three deliberate ones:"; \
		cat build/composer-validate-strict.unexpected; \
		exit 1; \
	fi
	@echo "$(GREEN)[SUCCESS]$(NC) composer validate --strict: only the three deliberate warnings"

# Packagist resolves a version from the TAG NAME, while composer.json here also carries an
# explicit `version`. When those two disagree Packagist publishes the field's value under the
# tag's name - a release that installs as a version nobody tagged. This is the agreement check the
# fleet requires, and it also refuses a version with no RELEASE.md entry, because
# CURRENT_RELEASE_NOTES would then slice out nothing and `gh release create` would ship empty
# notes without complaining.
check_version_agreement: ## Fail unless ONDEWO_S2T_VERSION, composer.json, RELEASE.md and (when HEAD is a tag) the git tag all agree
	@name=`php -r 'echo json_decode(file_get_contents("composer.json"), true)["name"] ?? "";'`; \
	version=`php -r 'echo json_decode(file_get_contents("composer.json"), true)["version"] ?? "";'`; \
	if [ "$$name" != "${PACKAGIST_PACKAGE}" ]; then \
		echo "$(RED)[ERROR]$(NC) composer.json name is '$$name' but the Packagist package is '${PACKAGIST_PACKAGE}'"; exit 1; fi; \
	if [ "$$version" != "${ONDEWO_S2T_VERSION}" ]; then \
		echo "$(RED)[ERROR]$(NC) composer.json version is '$$version' but ONDEWO_S2T_VERSION is '${ONDEWO_S2T_VERSION}' - run 'make update_composer_version'"; exit 1; fi; \
	grep -qF "Release ONDEWO S2T PHP Client ${ONDEWO_S2T_VERSION}" RELEASE.md \
		|| { echo "$(RED)[ERROR]$(NC) RELEASE.md has no '## Release ONDEWO S2T PHP Client ${ONDEWO_S2T_VERSION}' entry - the GitHub release would ship empty notes"; exit 1; }; \
	tag="${RELEASE_TAG}"; \
	[ -n "$$tag" ] || tag=`git describe --exact-match --tags HEAD 2>/dev/null || true`; \
	if [ -z "$$tag" ]; then \
		echo "$(BLUE)[INFO]$(NC) HEAD is not a release tag - tag agreement not applicable (set RELEASE_TAG to force the check)"; \
	elif [ "$$tag" != "${ONDEWO_S2T_VERSION}" ]; then \
		echo "$(RED)[ERROR]$(NC) git tag '$$tag' does not match ONDEWO_S2T_VERSION '${ONDEWO_S2T_VERSION}' - Packagist would publish the tag under the wrong version"; exit 1; \
	else \
		echo "$(BLUE)[INFO]$(NC) git tag '$$tag' agrees with ONDEWO_S2T_VERSION"; \
	fi
	@echo "$(GREEN)[SUCCESS]$(NC) ${PACKAGIST_PACKAGE} ${ONDEWO_S2T_VERSION}: version fields agree"

# The update API identifies the package by its VCS url, NOT by its composer name: ping the wrong
# url with valid credentials and Packagist answers 200 for a package that is not this one. So the
# payload is checked against composer.json's own support.source, which is what was submitted.
check_packagist_payload: ## Fail unless the Packagist update payload is well-formed JSON pointing at this repository
	@mkdir -p build
	@printf '%s\n' '$(PACKAGIST_UPDATE_PAYLOAD)' > build/packagist-update-payload.json
	@url=`php -r 'echo json_decode(file_get_contents("build/packagist-update-payload.json"), true)["repository"]["url"] ?? "";'`; \
	source=`php -r 'echo json_decode(file_get_contents("composer.json"), true)["support"]["source"] ?? "";'`; \
	if [ -z "$$url" ]; then \
		echo "$(RED)[ERROR]$(NC) the update payload is not valid JSON or carries no repository.url:"; \
		cat build/packagist-update-payload.json; exit 1; fi; \
	if [ "$$url" != "$$source" ]; then \
		echo "$(RED)[ERROR]$(NC) the update payload points at '$$url' but composer.json support.source is '$$source'"; exit 1; fi
	@echo "$(GREEN)[SUCCESS]$(NC) Packagist update payload points at ${PACKAGIST_REPOSITORY_URL}"

# Never prints either credential, only whether it is usable. Both the placeholder AND the empty
# string have to be rejected: a devops-accounts file without the line leaves the placeholder, an
# empty `NAME=` line expands to the EMPTY string, and either would post an unauthenticated ping
# after the tag has already been pushed.
check_packagist_credentials: ## Fail unless PACKAGIST_USERNAME and PACKAGIST_API_TOKEN are set
	@if [ -z "$${PACKAGIST_USERNAME}" ] || [ "$${PACKAGIST_USERNAME}" = "ENTER_HERE_YOUR_PACKAGIST_USERNAME" ]; then \
		echo "$(RED)[ERROR]$(NC) PACKAGIST_USERNAME is not set - it is the Packagist login name (ondewo-devops-accounts: account_packagist.env)"; exit 1; fi
	@if [ -z "$${PACKAGIST_API_TOKEN}" ] || [ "$${PACKAGIST_API_TOKEN}" = "ENTER_HERE_YOUR_PACKAGIST_API_TOKEN" ]; then \
		echo "$(RED)[ERROR]$(NC) PACKAGIST_API_TOKEN is not set - it is the token from https://packagist.org/profile/ 'Show API token' (ondewo-devops-accounts: account_packagist.env)"; exit 1; fi
	@echo "$(GREEN)[SUCCESS]$(NC) Packagist credentials are set"

# Prefixed with @ so neither credential reaches the build log, and written against the EXPORTED
# shell variables (this Makefile exports everything, see line 1) rather than against
# $(PACKAGIST_API_TOKEN): should the @ ever be dropped, make then echoes the variable NAME instead
# of the token. --fail is deliberately NOT used - the http code is inspected by hand so a 403 is
# reported as "bad credentials" instead of curl's bare exit 22.
#
# THE CREDENTIALS ARE NOT IN THE URL. Packagist's ApiController::findUser() accepts three spellings
# - POST body parameters, ?username=&apiToken= query parameters, and an `Authorization: Bearer
# <username>:<apiToken>` header that takes precedence over the other two - and only the header keeps
# the token out of places that are not ours. The query parameter put it in /proc/<pid>/cmdline,
# which is world-readable, in the shell history of anyone who copied the command, and in the access
# log of every proxy on the way. The POST body is no use here: Symfony reads body parameters out of
# FORM encoding, and the body of this request is the JSON payload above.
#
# The header itself is fed to curl through `--config -` on STDIN rather than a `-H` argument,
# because a -H argument would land in the process table exactly like the query parameter did.
# printf is a shell builtin, so the only command line that ever holds the values is curl's - and
# curl's holds neither.
packagist_update: ## Ping the Packagist update API so it crawls the tags of this repository
	@mkdir -p build
	@echo "$(BLUE)[INFO]$(NC) Asking Packagist to crawl ${PACKAGIST_REPOSITORY_URL} ..."
# Packagist answers 202 Accepted on success - the crawl is queued, not finished - and 200 only on
# some paths. Both are success; the authoritative signal is status=success in the body. Demanding
# 200 alone reported a completed publish as a credentials failure.
# NOTE: keep comments OUT of the backslash-continued block below. A `#` line inside it is a SHELL
# comment that swallows the rest of the joined line, so the http-code test then ran in a new shell
# with an empty `code` and failed EVERY publish, 202 included.
	@code=`printf 'header = "Authorization: Bearer %s:%s"\n' "$${PACKAGIST_USERNAME}" "$${PACKAGIST_API_TOKEN}" \
		| curl --silent --show-error --location --config - \
		--output build/packagist-update-response.json --write-out '%{http_code}' \
		-X POST -H 'Content-Type: application/json' \
		-d '$(PACKAGIST_UPDATE_PAYLOAD)' \
		"${PACKAGIST_UPDATE_API}"`; \
	echo "$(BLUE)[INFO]$(NC) Packagist answered HTTP $$code"; \
	cat build/packagist-update-response.json; echo; \
	if [ "$$code" != "200" ] && [ "$$code" != "202" ]; then \
		echo "$(RED)[ERROR]$(NC) Packagist rejected the update (HTTP $$code). 40x means the credentials are wrong or ${PACKAGIST_PACKAGE} has never been submitted - see README 'Publishing to Packagist'"; \
		exit 1; \
	fi; \
	grep -q '"status" *: *"success"' build/packagist-update-response.json \
		|| { echo "$(RED)[ERROR]$(NC) Packagist returned HTTP $$code without status=success - see the response above"; exit 1; }
	@echo "$(GREEN)[SUCCESS]$(NC) Packagist queued a crawl of ${PACKAGIST_REPOSITORY_URL}"

########################################################
#		DEVOPS-ACCOUNTS

# The two update_* targets run BEFORE spc: ondewo-s2t-api's release_client rewrites only this
# Makefile's version and pin lines, so composer.json (spc Test 3) and the README would otherwise still
# carry the previous version. `release` commits both files.
ondewo_release: update_composer_version update_readme_version spc clone_devops_accounts run_release_with_devops ## Release with credentials from devops-accounts repo
	@rm -rf ${DEVOPS_ACCOUNT_GIT}

clone_devops_accounts: ## Clones devops-accounts repo
	if [ -d $(DEVOPS_ACCOUNT_GIT) ]; then rm -Rf $(DEVOPS_ACCOUNT_GIT); fi
	git clone git@bitbucket.org:ondewo/${DEVOPS_ACCOUNT_GIT}.git

# Exactly the three credentials `release` uses, each by an ANCHORED `^NAME=` match. The devops files
# carry '#' comment lines that mention variable names, so an unanchored grep can return a comment,
# and a '#' reaching a command line comments out every credential after it.
# The values are exported into the sub-make's ENVIRONMENT: `make release NAME=<value>` would put every
# value on make's argv, which /proc/<pid>/cmdline shows to every user on the host.
run_release_with_devops: ## Gets Credentials from devops-repo and run release command with them
	@set -a \
		&& eval "$$(grep -hE '^GITHUB_GH_TOKEN=' ${DEVOPS_ACCOUNT_DIR}/account_github.env; \
			grep -hE '^(PACKAGIST_USERNAME|PACKAGIST_API_TOKEN)=' ${DEVOPS_ACCOUNT_DIR}/account_packagist.env)" \
		&& set +a \
		&& $(MAKE) release

# All three tests used to match on a SUBSTRING, which made each of them lie:
#   * `git branch --all | grep "release/7.1.0"` also matches release/7.1.0-rc1 and
#     release/17.1.0, so an unrelated branch blocks the release. Anchored on both ends now, the
#     way cpp/ and csharp/ spell it: `(^|[ /])release/<escaped version>$$` - `[ /]` so that
#     `remotes/origin/release/7.1.0` still counts, and $(subst .,\.,...) so the dots of the
#     version are literal dots rather than "any character".
#   * `git tag --list | grep "7.1.0"` also matches 7.1.0 as a substring of 17.1.0 and of 7.1.01.
#     `grep -Fx` is a fixed-string, whole-line match: only the tag itself.
#   * Test 3 compared the composer.json LINE against the empty string, so it passed for ANY
#     version the field happened to hold - including the previous release's, which is exactly the
#     mistake it exists to catch. Compare the VALUE to ONDEWO_S2T_VERSION, the way rust/ and
#     java/ do. `test -f` first so a missing manifest reports the version mismatch instead of a
#     sed error.
spc: ## Checks if the Release Branch, Tag and composer.json version already exist
	$(eval filtered_branches:= $(shell git branch --all | grep -E "(^|[ /])release/$(subst .,\.,${ONDEWO_S2T_VERSION})$$"))
	$(eval filtered_tags:= $(shell git tag --list | grep -Fx "${ONDEWO_S2T_VERSION}"))
	$(eval composer_version:= $(shell test -f composer.json && sed -n 's|^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\(.*\)".*|\1|p' composer.json | head -n 1))
	@if test "$(filtered_branches)" != ""; then echo "-- Test 1: Branch exists!!" && exit 1; else echo "-- Test 1: Branch is fine";fi
	@if test "$(filtered_tags)" != ""; then echo "-- Test 2: Tag exists!!" && exit 1; else echo "-- Test 2: Tag is fine";fi
	@if test "$(composer_version)" != "${ONDEWO_S2T_VERSION}"; then \
		echo "-- Test 3: composer.json is at '$(composer_version)', not ${ONDEWO_S2T_VERSION} - run 'make update_composer_version'!!"; exit 1; \
	else echo "-- Test 3: composer.json is fine"; fi
