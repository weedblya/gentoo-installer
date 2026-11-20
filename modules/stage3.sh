#!/usr/bin/env bash
# =============================================================================
# Stage3 Download & Extraction Module
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

download_stage3() {
  step "Downloading Stage3"

  load_config

  # Check available disk space (need at least 2GB for stage3 and extraction)
  local available_space_mb
  available_space_mb=$(df -m "$MNT" | tail -1 | awk '{print $4}')
  if [[ "$available_space_mb" -lt 2048 ]]; then
    die "Insufficient disk space: ${available_space_mb}MB available, need at least 2048MB"
  fi

  local stage3_base="https://distfiles.gentoo.org/releases/amd64/autobuilds"
  local latest_txt="$stage3_base/latest-stage3.txt"

  # Determine stage3 variant based on init system
  local stage3_pattern="stage3-amd64-openrc"
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    stage3_pattern="stage3-amd64-systemd"
  fi

  info "Fetching latest stage3 metadata..."
  local metadata
  local retry_count=0
  while [[ $retry_count -lt 3 ]]; do
    if metadata=$(curl -s --connect-timeout 30 --max-time 60 "$latest_txt"); then
      break
    fi
    ((retry_count++))
    [[ $retry_count -lt 3 ]] && { warn "Retry $retry_count/3..."; sleep 2; } || die "Failed to fetch stage3 metadata after 3 attempts"
  done

  # Parse the txt file to find the appropriate stage3 tarball
  # Format: "20261115T170104Z/stage3-amd64-openrc-20261115T170104Z.tar.xz 276277944"
  local filepath
  filepath=$(printf '%s' "$metadata" | grep -v '^#' | grep -v '^-' | grep "\.tar\.xz" | grep "$stage3_pattern" | grep -v "desktop\|hardened\|musl\|llvm\|nomultilib" | head -1 | awk '{print $1}')

  [[ -n "$filepath" ]] || die "Failed to find $stage3_pattern stage3 in metadata"

  local stage3_url="$stage3_base/$filepath"
  local filename="${filepath##*/}"
  local target="$MNT/stage3.tar.xz"

  info "Downloading: $filename"
  info "URL: $stage3_url"
  wget --timeout=60 --tries=3 --show-progress -O "$target" "$stage3_url" || die "Failed to download stage3 from $stage3_url"

  info "Extracting stage3..."
  tar -xpf "$target" -C "$MNT" --xattrs-include='*.*' --numeric-owner || die "Failed to extract stage3"

  rm -f "$target"
  success "Stage3 installed"
  record OK "stage3" "extracted to $MNT"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root
  download_stage3
fi
