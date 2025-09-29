#!/usr/bin/env bash
# Robust perf installer for Ubuntu (incl. AWS kernels) & Amazon Linux
# - Installs packages
# - Wires Ubuntu wrapper to a real perf helper (no warnings, no loops)
# - (Optional) Sets persistent sysctl to allow perf to run by default
set -euo pipefail

log(){ printf '%s\n' "$*"; }
info(){ log "[INFO] $*"; }
warn(){ log "[WARN] $*"; }

PERF_TUNE_SYSCTL="${PERF_TUNE_SYSCTL:-1}"   # set to 0 to skip sysctl tuning

# choose a real perf binary on disk (resolve symlinks, pick newest)
pick_real_perf() {
  local list real
  list="$(ls -1 /usr/lib/linux-tools-*/perf /usr/lib/linux-tools/*/perf 2>/dev/null || true)"
  if [ -n "${list}" ]; then
    real="$(
      while read -r f; do [ -n "$f" ] && readlink -f "$f"; done <<<"${list}" \
      | awk 'NF' | sort -uV | tail -n1
    )"
    if [ -n "${real}" ] && [ -x "${real}" ]; then
      printf '%s' "$real"; return 0
    fi
  fi
  if [ -x /usr/bin/perf ]; then
    if head -c4 /usr/bin/perf 2>/dev/null | grep -q $'\x7fELF'; then
      printf '%s' "/usr/bin/perf"; return 0
    fi
  fi
  return 1
}

wire_ubuntu_wrapper() {
  local kver base real
  kver="$(uname -r)"
  base="${kver%-aws}"

  update-alternatives --remove-all perf 2>/dev/null || true
  [ -L "/usr/local/bin/perf" ] && rm -f "/usr/local/bin/perf"
  [ -L "/usr/lib/linux-tools-${kver}/perf" ] && rm -f "/usr/lib/linux-tools-${kver}/perf"
  [ -L "/usr/lib/linux-tools/${kver}/perf" ] && rm -f "/usr/lib/linux-tools/${kver}/perf"

  real="$(pick_real_perf || true)"
  if [ -z "${real:-}" ]; then
    warn "No real perf helper found on disk; trying more packages…"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      linux-tools-common linux-tools-generic \
      "linux-tools-${kver}" "linux-cloud-tools-${kver}" \
      "linux-tools-${base}" "linux-cloud-tools-${base}" \
      linux-tools-aws linux-cloud-tools-aws || true
    real="$(pick_real_perf || true)"
  fi
  if [ -z "${real:-}" ]; then
    warn "Could not locate any usable perf helper after package installs."
    return 1
  fi

  mkdir -p "/usr/lib/linux-tools-${kver}" "/usr/lib/linux-tools/${kver}"
  ln -s "${real}" "/usr/lib/linux-tools-${kver}/perf"
  ln -s "${real}" "/usr/lib/linux-tools/${kver}/perf"
  ln -s "${real}" "/usr/local/bin/perf"

  if [ -L /usr/bin/perf ]; then
    update-alternatives --install /usr/bin/perf perf "/usr/lib/linux-tools-${kver}/perf" 100 || true
    update-alternatives --set perf "/usr/lib/linux-tools-${kver}/perf" || true
  fi

  hash -r || true
  info "Wired perf helper for ${kver} -> $(/usr/local/bin/perf --version 2>/dev/null || echo "${real}")"
}

install_ubuntu() {
  local kver base
  kver="$(uname -r)"
  base="${kver%-aws}"

  info "Installing perf packages via apt (kernel: ${kver})…"
  apt-get update -y

  # Detect Ubuntu release
  local release=""
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    release="$VERSION_ID"
  fi

  if dpkg --compare-versions "$release" le "22.04"; then
    # Ubuntu 22.04 (Jammy) and earlier - include cloud-tools
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      linux-tools-common linux-tools-generic \
      "linux-tools-${kver}" "linux-cloud-tools-${kver}" || true

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      "linux-tools-${base}" "linux-cloud-tools-${base}" \
      linux-tools-aws linux-cloud-tools-aws || true
  else
    # Ubuntu 24.04 (Noble) and newer - no cloud-tools packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      linux-tools-common linux-tools-generic \
      "linux-tools-${kver}" "linux-tools-${base}" linux-tools-aws || true
  fi

  wire_ubuntu_wrapper || true
}

install_rpm_family() {
  if command -v dnf >/dev/null 2>&1; then
    info "Installing perf via dnf…"
    dnf install -y perf || true
  else
    info "Installing perf via yum…"
    yum install -y perf || true
  fi  
  if ! command -v perf >/dev/null 2>&1; then
    warn "perf binary not found after install; check repos on this image."
  fi
}

tune_sysctl() {
  [ "${PERF_TUNE_SYSCTL}" = "1" ] || { info "Skipping sysctl tuning (PERF_TUNE_SYSCTL=0)."; return 0; }
  info "Setting persistent sysctl for perf (paranoid=2, kptr_restrict=0)…"
  cat >/etc/sysctl.d/99-perf.conf <<'EOF'
# Managed by arm-linux-migration-tools
kernel.perf_event_paranoid = 2
kernel.kptr_restrict = 0
EOF
  sysctl --system >/dev/null || true
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then exec sudo -E -- "$0" "$@"; else
      echo "[ERROR] Must run as root." >&2; exit 1; fi
  fi

  if [ -f /etc/os-release ]; then . /etc/os-release; else ID=""; fi

  case "${ID:-}" in
    ubuntu|debian) install_ubuntu ;;
    amzn|rhel|centos|fedora) install_rpm_family ;;
    *) warn "Unsupported OS ID '${ID:-unknown}'. Attempting Ubuntu path…"; install_ubuntu || true ;;
  esac

  if perf --version >/dev/null 2>&1; then
    info "perf ready: $(perf --version)"
  else
    if [ -x "/usr/lib/linux-tools-$(uname -r)/perf" ]; then
      info "perf helper: $(/usr/lib/linux-tools-$(uname -r)/perf --version 2>/dev/null || echo present)"
    else
      warn "perf still not available on PATH; wrapper may be present but unwired."
    fi
  fi

  tune_sysctl

  ( perf stat -e task-clock sleep 0.1 >/dev/null 2>&1 && info "perf stat smoke: OK" ) || \
    warn "perf stat smoke failed (consider checking kernel.perf_event_paranoid)."
}
# Apply sysctl immediately for current session
if [ "${PERF_TUNE_SYSCTL}" = "1" ]; then
  echo 2 > /proc/sys/kernel/perf_event_paranoid || true
  echo 0 > /proc/sys/kernel/kptr_restrict || true
fi
main "$@"
exit 0