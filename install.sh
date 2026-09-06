#!/usr/bin/env bash
#
# install.sh — build and install Qaf (the .qf language) on x86-64 Linux.
#
# What it does:
#   1. checks the platform and build dependencies (binutils, make)
#   2. reports optional runtime dependencies (OpenCL loader, ICD vendors, GPU)
#   3. builds qafc with `make`
#   4. runs the test suite
#   5. installs qafc + a `qaf` command + the standard library + examples
#   6. verifies the installed binary end-to-end from a neutral directory
#
# Usage:
#   ./install.sh                     # PREFIX=/usr/local (falls back to ~/.local)
#   ./install.sh --prefix ~/qaf      # install into a custom prefix
#   ./install.sh --no-test           # skip the test suite
#   ./install.sh --install-deps      # (root) install binutils + make via the
#                                    #   distro package manager first
#   ./install.sh --uninstall         # remove everything install.sh added
#   ./install.sh --help
#
set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------- helpers --
info() { printf '\033[1;36m[qaf]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[qaf]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[qaf] warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[qaf] error:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Qaf installer — build, test and install the Qaf programming language.

USAGE:
    ./install.sh [options]

OPTIONS:
    --prefix DIR        install under DIR (default: /usr/local, or ~/.local
                        when /usr/local is not writable by the current user)
    --no-test           skip the test suite
    --install-deps      install binutils + make with the distro package
                        manager (needs root/sudo)
    --uninstall         remove the files this installer installs
    -h, --help          show this help and exit
    -V, --version       show the installer version and exit

ENVIRONMENT:
    PREFIX=DIR          same as --prefix
EOF
}

opt_prefix=""
opt_no_test=0
opt_install_deps=0
opt_uninstall=0

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)            opt_prefix="${2:-}"; test -n "$opt_prefix" || die "--prefix needs a directory"; shift 2 ;;
        --no-test)           opt_no_test=1; shift ;;
        --install-deps)      opt_install_deps=1; shift ;;
        --uninstall)         opt_uninstall=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        -V|--version)        printf 'Qaf installer %s\n' "$VERSION"; exit 0 ;;
        *)                   die "unknown option: $1 (try --help)" ;;
    esac
done

# --------------------------------------------------------- platform and repo --
[ "$(uname -s)" = "Linux" ] || die "Qaf targets Linux (this system: $(uname -s))"
case "$(uname -m)" in
    x86_64|amd64) : ;;
    *) die "Qaf's JIT emits x86-64 code only (this system: $(uname -m))" ;;
esac

test -f "$SCRIPT_DIR/Makefile" && test -d "$SCRIPT_DIR/src" \
    || die "install.sh must be run from the Qaf source tree"

# ------------------------------------------------------------- build deps --
need=""
command -v as  >/dev/null 2>&1 || need="$need as"
command -v ld  >/dev/null 2>&1 || need="$need ld"
command -v make>/dev/null 2>&1 || need="$need make"

if [ -n "$need" ]; then
    if [ "$opt_install_deps" = 1 ]; then
        if [ "$(id -u)" != 0 ]; then
            die "--install-deps needs root (try: sudo $0 --install-deps)"
        fi
        info "installing missing build dependencies:$need"
        . /etc/os-release 2>/dev/null || true
        case "${ID:-}" in
            debian|ubuntu|linuxmint|pop) apt-get install -y binutils make ;;
            fedora|rhel|centos|rocky|alma) dnf install -y binutils make ;;
            arch) pacman -S --noconfirm binutils make ;;
            opensuse*|suse) zypper install -y binutils make ;;
            alpine) apk add --no-cache binutils make ;;
            *) die "distro '$ID' is not wired into --install-deps; install binutils and make manually" ;;
        esac
    else
        die "missing build dependencies:$need\n       install binutils and make, then re-run (or re-run as: $0 --install-deps)"
    fi
fi

# ------------------------------------------------------------ optional deps --
# OpenCL is not required to run Qaf today: it is the foundation for the GPU
# bindings tracked in docs/gpu.md. We detect and report it so installs know
# whether GPU support is available on this machine.
opencl_loader="no"; opencl_icd="no"; opencl_gpu="no"; ld_linux="no"
if /sbin/ldconfig -p 2>/dev/null | grep -qi "libOpenCL.so" || \
   ls /usr/lib/x86_64-linux-gnu/libOpenCL.so* 2>/dev/null | grep -q .; then
    opencl_loader="yes"
fi
if [ -d /etc/OpenCL/vendors ] && [ -n "$(ls /etc/OpenCL/vendors 2>/dev/null)" ]; then
    opencl_icd="yes"
fi
if ls /dev/dri/renderD* >/dev/null 2>&1; then
    opencl_gpu="yes"
fi
if [ -e /lib64/ld-linux-x86-64.so.2 ] || [ -e /lib/ld-linux-x86-64.so.2 ]; then
    ld_linux="yes"
fi

info "platform: $(uname -m) Linux"
info "build deps: ok (as, ld, make)"
info "optional deps: OpenCL loader=$opencl_loader  ICD vendors=$opencl_icd  GPU render node=$opencl_gpu  ld-linux=$ld_linux"
if [ "$opencl_loader" = "no" ]; then
    warn "no OpenCL loader found (libOpenCL.so) — fine for today, GPU support needs it later"
fi

# -------------------------------------------------------------------- build --
info "building qafc in $SCRIPT_DIR ..."
make -C "$SCRIPT_DIR" >/dev/null

# --------------------------------------------------------------------- test --
if [ "$opt_no_test" = 1 ]; then
    info "skipping the test suite (--no-test)"
else
    info "running the test suite (JIT + interpreter modes)..."
    make -C "$SCRIPT_DIR" test < /dev/null || die "test suite failed — fix before installing"
fi

# ------------------------------------------------------------------- uninstall --
if [ "$opt_uninstall" = 1 ]; then
    if [ -z "$opt_prefix" ] && [ -n "${PREFIX:-}" ]; then opt_prefix="$PREFIX"; fi
    PREFIX_TO_REMOVE="${opt_prefix:-/usr/local}"
    info "uninstalling from $PREFIX_TO_REMOVE ..."
    make -C "$SCRIPT_DIR" uninstall PREFIX="$PREFIX_TO_REMOVE" || true
    ok "uninstalled."
    exit 0
fi

# ------------------------------------------------------------ choose prefix --
PREFIX="${opt_prefix:-${PREFIX:-/usr/local}}"
need_root_msg=""
if ! mkdir -p "$PREFIX" 2>/dev/null; then
    die "cannot create $PREFIX"
fi
if [ ! -w "$PREFIX" ] && [ "$(id -u)" != 0 ]; then
    warn "$PREFIX is not writable by $(whoami) — falling back to ~/.local"
    PREFIX="$HOME/.local"
    mkdir -p "$PREFIX" 2>/dev/null || die "cannot create $PREFIX"
fi
mkdir -p "$PREFIX/bin" 2>/dev/null || die "cannot create $PREFIX/bin"
info "installing to $PREFIX ..."

make -C "$SCRIPT_DIR" install PREFIX="$PREFIX"

BIN_QAF="$PREFIX/bin/qaf"
BIN_QAFC="$PREFIX/bin/qafc"
if [ ! -x "$BIN_QAFC" ] || [ ! -e "$BIN_QAF" ]; then
    die "install did not produce $PREFIX/bin/qafc / qaf"
fi

# --------------------------------------------------------------- verification --
# Prove the installed copy works from a neutral directory (not the repo), which
# is exactly the fresh-clone / install-then-use scenario: the program lives in
# /tmp, CWD is /tmp, so `from stdlib import *` can only resolve via the
# installed $PREFIX/lib/qaf search root.
info "verifying the installed binary from a neutral directory ..."
verify_dir="$(mktemp -d /tmp/qaf-verify.XXXXXX)"
trap 'rm -rf "$verify_dir"' EXIT
cat > "$verify_dir/verify.qf" <<'EOF'
from stdlib import *;
print gcd(48, 18);
print fib(10);
print list(1, 2, 3);
print sqrt(9.0);
EOF

run_verify() {
    local bin="$1" out line got i=0
    out="$("$bin" "$verify_dir/verify.qf" 2>&1)" || die "verification failed: $bin"
    for want in 6 55 "[1, 2, 3]" 3.0; do
        i=$((i + 1))
        got="$(printf '%s\n' "$out" | sed -n "${i}p")"
        [ "$got" = "$want" ] || die "verification mismatch (line $i): got '$got', want '$want'"
    done
}

(
    cd "$verify_dir"                     # neutral CWD: /tmp/qaf-verify.XXXX
    run_verify "$BIN_QAFC"
    run_verify "$BIN_QAF"                # the `qaf` command must behave identically
    "$BIN_QAF" "$PREFIX/share/qaf/examples/fib.qf" >/dev/null || die "installed example fib.qf failed"
    printf 'print 2 * 21;\n' | "$BIN_QAF" >/dev/null || die "REPL smoke test failed"
)
ok "verification passed (imports, examples, REPL all work from the installed copy)"

# ---------------------------------------------------------------------- path --
in_path=0
case ":$PATH:" in
    *":$PREFIX/bin:"*) in_path=1 ;;
esac
if [ "$in_path" = 0 ]; then
    warn "$PREFIX/bin is not on your PATH — add it with:"
    printf '        export PATH=%q/bin:$PATH\n' "$PREFIX"
fi

cat <<EOF

Qaf installed successfully.

    binary:     $BIN_QAFC
    command:    $BIN_QAF          (use \`qaf\` as a shortcut for \`qafc\`)
    stdlib:     $PREFIX/lib/qaf
    examples:   $PREFIX/share/qaf/examples

Try it:
    ${BIN_QAFC:-qaf} $PREFIX/share/qaf/examples/demo.qf
    qaf                                  # interactive REPL

Full documentation is in docs/ (installed to $PREFIX/share/doc/qaf).
EOF

exit 0