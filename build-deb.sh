#! /bin/bash

# Build the fadbad++ Debian package.
# Upstream sources come from the orig tarball (FADBAD++ 2.1 from fadbad.com),
# the Debian changes from HEAD: the package uses the 1.0 source format, so
# debian/ and the changes to the upstream files (Makefile, examples/Makefile,
# test/Makefile, test/TestAll.cpp) end up in the diff.gz.

# set -x # force debug
set -eo pipefail # add flag to stop when command returns an error

PACKAGE=fadbad++

# LNCMI apt repository, used to reuse the already published orig tarball
: ${REPO_URL:="http://euler.lncmig.local/~christophe.trophime@LNCMIG.local/debian"}

usage(){
   echo ""
   echo "Description:"
   echo "               Builds the debian package from the orig tarball"
   echo "               and the sources from HEAD"
   echo ""
   echo "Usage:"
   echo "               $(basename "$0") [ <option> ] ... ]"
   echo ""
   echo "Options:"
   echo "-a <arch>      Specify the architecture to build for (eg. amd64, arm64)"
   echo "-d <dist>      Specify the distribution to use (default: trixie)"
   echo "-v <x.y>       Specify upstream version to build (default: from debian/changelog)"
   echo "-t             Only fetch the orig tarball"
   echo ""
   echo "Environment:"
   echo "ORIG_DIR            where the orig tarball is looked for and downloaded"
   echo "                    (default: the parent directory of the git repository)"
   echo "REPO_URL            LNCMI apt repository (default: $REPO_URL)"
   echo "LNCMI_APT_KEY_FILE  public key of that repository"
   echo "                    (default: ../apt-depot/lncmi-repo-ci-public-key.asc)"
   echo "UPSTREAM_URL        upstream tarball, used when none is published"
   echo "                    (default: http://www.fadbad.com/download/FADBAD++-<version>.tar.gz)"
   echo ""
   exit $1
}

ACTION=build
while getopts "ha:d:v:t" option ; do
   case $option in
       h ) usage 0 ;;
       a ) ARCH=$OPTARG ;;
       d ) DIST=$OPTARG ;;
       v ) VERSION=$OPTARG ;;
       t ) ACTION=tarball ;;
       ? ) usage 1 ;;
   esac
done
# shift to have the good number of other args
shift $((OPTIND - 1))

die(){ echo "Error: $*" >&2; exit 1; }
warn(){ echo "Warning: $*" >&2; }

# temporary directories, removed on exit
CLEANUP=()
trap 'rm -rf "${CLEANUP[@]}"' EXIT
# mktempdir <var>: create a temporary directory and store its path in <var>
# (not through $(...), whose subshell would not update CLEANUP)
mktempdir(){ local d; d=$(mktemp -d); CLEANUP+=("$d"); printf -v "$1" '%s' "$d"; }

TOPDIR=$(git rev-parse --show-toplevel)
cd "$TOPDIR"

# add parameters
: ${VERSION:="$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//')"}
: ${DIST:="trixie"}
: ${ARCH:="amd64"}
: ${ORIG_DIR:="$(dirname "$TOPDIR")"}
: ${LNCMI_APT_KEY_FILE:="$TOPDIR/../apt-depot/lncmi-repo-ci-public-key.asc"}
: ${UPSTREAM_URL:="http://www.fadbad.com/download/FADBAD++-${VERSION}.tar.gz"}

ORIG=${ORIG_DIR}/${PACKAGE}_${VERSION}.orig.tar.gz

# Download the orig tarball already published in the LNCMI repository, if
# any: the published one is a repack of the upstream tarball, a downloaded
# one would differ and the repository would reject it.
# Checked through the signed InRelease -> Sources.gz -> orig tarball chain.
# Called as "fetch_published_orig && ...", where set -e does not apply:
# every step checks its own errors.
fetch_published_orig(){
    local name tmp sha dir osha
    name=$(basename "$ORIG")
    mktempdir tmp

    if ! curl -fsS -m 30 "$REPO_URL/dists/$DIST/InRelease" -o "$tmp/InRelease"; then
        warn "cannot reach $REPO_URL, not checking for a published $name"
        return 1
    fi
    [ -r "$LNCMI_APT_KEY_FILE" ] \
        || die "cannot read LNCMI_APT_KEY_FILE=$LNCMI_APT_KEY_FILE to verify $REPO_URL"
    gpg --dearmor < "$LNCMI_APT_KEY_FILE" > "$tmp/key.gpg" \
        || die "cannot read the key in $LNCMI_APT_KEY_FILE"
    gpgv --quiet --keyring "$tmp/key.gpg" --output "$tmp/Release" "$tmp/InRelease" 2>/dev/null \
        || die "bad signature on $REPO_URL/dists/$DIST/InRelease"

    sha=$(awk '/^SHA256:/ {s=1; next} /^[^ ]/ {s=0} s && $3 == "main/source/Sources.gz" {print $1}' "$tmp/Release")
    [ -n "$sha" ] || return 1
    curl -fsS -m 60 "$REPO_URL/dists/$DIST/main/source/Sources.gz" -o "$tmp/Sources.gz" \
        || die "cannot download $REPO_URL/dists/$DIST/main/source/Sources.gz"
    echo "$sha  $tmp/Sources.gz" | sha256sum -c --quiet - || die "Sources.gz does not match InRelease"

    read -r dir osha < <(gzip -dc "$tmp/Sources.gz" | awk -v P="$PACKAGE" -v F="$name" '
        /^Package:/            {pkg = $2; dir = ""; osha = ""}
        /^Directory:/          {dir = $2}
        /^Checksums-Sha256:/   {s = 1; next}
        /^[^ ]/                {s = 0}
        s && $3 == F           {osha = $1}
        /^$/ && pkg == P && osha != "" {print dir, osha; exit}
        END { if (pkg == P && osha != "") print dir, osha }') || true
    [ -n "$osha" ] || return 1

    echo "-- Downloading the published $name"
    curl -fsS -m 300 "$REPO_URL/$dir/$name" -o "$ORIG.part" \
        || { rm -f "$ORIG.part"; die "cannot download $REPO_URL/$dir/$name"; }
    echo "$osha  $ORIG.part" | sha256sum -c --quiet - || { rm -f "$ORIG.part"; die "$name does not match Sources.gz"; }
    mv "$ORIG.part" "$ORIG"
}

# Nothing published for $DIST yet: the upstream release tarball is the orig.
fetch_upstream_orig(){
    echo "-- Downloading $UPSTREAM_URL"
    curl -fsSL -m 300 "$UPSTREAM_URL" -o "$ORIG.part" \
        || { rm -f "$ORIG.part"; die "cannot download $UPSTREAM_URL"; }
    gzip -t "$ORIG.part" || { rm -f "$ORIG.part"; die "$UPSTREAM_URL is not a gzip tarball"; }
    mv "$ORIG.part" "$ORIG"
}

# The orig tarball is the upstream release, identical for every Debian
# revision: reuse it, else fetch the published one, else the upstream one.
# It is never recreated from git, whose tree already carries the Debian
# changes.
ensure_orig(){
    if [ -f "$ORIG" ]; then
        echo "-- Reusing $ORIG"
        return
    fi
    fetch_published_orig && return
    fetch_upstream_orig
}

do_tarball(){
    ensure_orig
    echo "$ORIG"
}

do_build(){
    [ -z "$(git status --porcelain)" ] \
        || die "uncommitted changes; they would be ignored (the sources are taken from HEAD)"
    [ "$(dpkg-parsechangelog -S Distribution)" != "UNRELEASED" ] \
        || warn "debian/changelog distribution is UNRELEASED"

    ensure_orig

    local work
    mktempdir work
    local src="$work/${PACKAGE}-${VERSION}"
    mkdir -p "$src"
    cp "$ORIG" "$work/"
    # the git-only files are marked export-ignore in .gitattributes
    git archive HEAD | tar -C "$src" -x

    cd "$src"
    # sudo-rs ignores 'sudo -E': keep DIST/ARCH and load the user's pbuilderrc explicitly
    DIST=${DIST} ARCH=${ARCH} pdebuild --pbuilderroot "sudo --preserve-env=DIST,ARCH" \
        --configfile "$HOME/.pbuilderrc"
}

do_$ACTION

# # upload new package to Lncmi package repository
# cd /var/cache/pbuilder/$DIST-$ARCH/results
# dupload -t euler_$DIST
