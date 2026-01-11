#!/bin/sh

# Installation script for zapret SPB strategy
# OpenWrt-only: fetches repo files into /opt/zapret, applies config.yaml to UCI, runs /opt/zapret/sync_config.sh

set -e

# Repo configuration (override via env)
REPO_OWNER="${REPO_OWNER:-blitss}"
REPO_NAME="${REPO_NAME:-zapret-spb-strategy}"
REPO_REF="${REPO_REF:-main}" # branch or tag
RAW_BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}"
API_BASE_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
ZAPRET_DIR="/opt/zapret"

echo "=== Zapret SPB Strategy Installer ==="
echo "Repository: ${REPO_OWNER}/${REPO_NAME}@${REPO_REF}"
echo ""

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

need_pkg() {
	# OpenWrt-only
	local pkg="$1"
	if opkg status "$pkg" 2>/dev/null | grep -q '^Status: install'; then
		return 0
	fi
	echo "Installing package: $pkg"
	opkg update >/dev/null
	opkg install "$pkg"
}

if ! need_cmd opkg; then
	echo "ERROR: this installer targets OpenWrt (opkg not found)."
	exit 1
fi

# deps: curl for downloads, jsonfilter for GitHub API JSON parsing, uci for config
need_cmd curl || need_pkg curl
need_cmd jsonfilter || need_pkg jsonfilter
need_cmd uci || { echo "ERROR: uci not found"; exit 1; }

# YAML parsing via yq (install temporarily if needed)
YQ_INSTALLED_BY_SCRIPT=0
if ! need_cmd yq; then
	need_pkg yq
	YQ_INSTALLED_BY_SCRIPT=1
fi

mkdir -p "$ZAPRET_DIR"

# Step 1: Fetch config.yaml
echo "Fetching configuration..."
CONFIG_YAML=$(mktemp)
curl -fsSL "${RAW_BASE_URL}/config.yaml" -o "$CONFIG_YAML"

# Step 2: Fetch all repo files (no git; use GitHub API tree; do not enumerate manually)
echo "Fetching repository files into ${ZAPRET_DIR} ..."

fetch_file() {
	local repo_path="$1"
	local target_path="${ZAPRET_DIR}/${repo_path}"
	local url="${RAW_BASE_URL}/${repo_path}"

	mkdir -p "$(dirname "$target_path")"
	echo "  - ${repo_path}"
	curl -fsSL "$url" -o "$target_path"
}

# Resolve default branch -> latest commit -> tree SHA (works even when REPO_REF is a branch)
repo_info_json="$(curl -fsSL "${API_BASE_URL}")"
default_branch="$(printf '%s' "$repo_info_json" | jsonfilter -e '@.default_branch')"

ref="${REPO_REF}"
if [ "$ref" = "main" ] || [ "$ref" = "master" ] || [ "$ref" = "$default_branch" ]; then
	# ok, keep as is
	:
fi

ref_json="$(curl -fsSL "${API_BASE_URL}/git/ref/heads/${ref}" 2>/dev/null || true)"
if [ -n "$ref_json" ]; then
	commit_sha="$(printf '%s' "$ref_json" | jsonfilter -e '@.object.sha')"
else
	# allow tags/commit SHA
	commit_sha="$ref"
fi

commit_json="$(curl -fsSL "${API_BASE_URL}/git/commits/${commit_sha}")"
tree_sha="$(printf '%s' "$commit_json" | jsonfilter -e '@.tree.sha')"

tree_json="$(curl -fsSL "${API_BASE_URL}/git/trees/${tree_sha}?recursive=1")"
paths="$(printf '%s' "$tree_json" | jsonfilter -e '@.tree[*].path')"
types="$(printf '%s' "$tree_json" | jsonfilter -e '@.tree[*].type')"

# jsonfilter outputs values line-by-line; we pair by line number
i=0
printf '%s\n' "$paths" | while IFS= read -r p; do
	i=$((i+1))
	t="$(printf '%s\n' "$types" | sed -n "${i}p")"
	[ "$t" = "blob" ] || continue

	# Skip GitHub workflows
	case "$p" in
		.github/workflows/*) continue ;;
	esac

	# Skip installer itself (optional; harmless if kept, but avoids overwriting while running)
	case "$p" in
		install.sh) continue ;;
	esac
	# Internal repo maintenance only (handled by workflow in repo, not on router)
	case "$p" in
		sync-lists.sh) continue ;;
	esac

	fetch_file "$p"
done

[ -d "${ZAPRET_DIR}/init.d" ] && find "${ZAPRET_DIR}/init.d" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

# Step 3: Parse config.yaml and configure UCI (lightweight YAML parsing for this file shape)
echo "Configuring OpenWrt UCI settings..."

# Function to set UCI value if different
set_uci_param() {
	local param="$1"
	local value="$2"
	local current_value="$(uci -q get "zapret.config.${param}")"

	if [ "$current_value" != "$value" ]; then
		echo "  Setting ${param}=${value}"
		uci set "zapret.config.${param}=$value"
	else
		echo "  Unchanged ${param}=${value}"
	fi
}

# Apply all top-level keys automatically (OpenWrt UCI: zapret.config.<KEY>)
# yq will return the literal block as a string with newlines.
echo "  Applying config.yaml keys..."
yq eval -r 'keys | .[]' "$CONFIG_YAML" | while IFS= read -r key; do
	[ -n "$key" ] || continue
	val="$(yq eval -r ".\"$key\"" "$CONFIG_YAML")"

	# normalize multiline strings (notably NFQWS_OPT)
	# - drop comment lines and empty lines
	# - join into a single space-separated string
	val="$(
		printf '%s' "$val" \
			| sed '/^[[:space:]]*#/d' \
			| sed '/^[[:space:]]*$/d' \
			| tr '\n' ' ' \
			| sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
	)"

	set_uci_param "$key" "$val"
done

# Commit UCI changes
echo "Committing UCI changes..."
uci commit zapret

# Cleanup
rm -f "$CONFIG_YAML"

# Step 4: Run sync_config.sh
if [ -f "${ZAPRET_DIR}/sync_config.sh" ]; then
    echo "Running sync_config.sh..."
    "${ZAPRET_DIR}/sync_config.sh"
else
    echo "Warning: ${ZAPRET_DIR}/sync_config.sh not found, skipping."
fi

echo ""
echo "=== Installation complete! ==="
echo "Please restart zapret service: /etc/init.d/zapret restart"

# Remove yq if we installed it just for this run
if [ "$YQ_INSTALLED_BY_SCRIPT" -eq 1 ]; then
	echo "Removing temporary package: yq"
	opkg remove yq >/dev/null 2>&1 || true
fi
