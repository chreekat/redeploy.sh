#!/usr/bin/env bash

# Usage:
#        ./redeploy.sh [-f] <system>

# Redeploys a server. Enforces that the last-deployed state is recorded in
# redeploy_config.sh. This might be more pain than it's worth, but the idea was
# to keep track of deployment conflicts since there are multiple people who do
# them. Better ideas welcome.

# Since this deploys to a remote server, /etc/nixos is unused on that server.

# Must be defined in redeploy_config.sh
declare -A target old nixos_rebuild_args

# shellcheck disable=SC1091
. redeploy_config.sh

force=false

usage() {
    >&2 echo "Usage: $0 [-f] <system> [nixos-rebuild args...]"
    exit 1
}

while getopts ":f" opt; do
    case "$opt" in
        f)
            force=true
            ;;
        \?)
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ ${1:-} == '--' ]]; then
    shift
fi

if [[ $# -lt 1 ]]; then
    usage
fi

system="$1"
shift

rebuild () {
    # Extract a string into an array split on whitespace because of SC2206,
    # which is because of SC2086 when using $args below. All because bash
    # doesn't have nested associative arrays.
    read -r -a args <<<"${nixos_rebuild_args["$system"]:-}"

    nixos-rebuild --use-substitutes "${args[@]}" --flake ".#${system}" "$@"
}

if [[ $(type -t redeploy_prehook) == "function" ]]; then
    redeploy_prehook "$system"
fi

rebuild build "$@"

new="$(readlink result)"
current="$(ssh "${target["$system"]}" readlink /run/current-system)"

# If old == new, we've given permission to deploy the new system.
if [[ ${old["$system"]} != "$new" ]]; then
    if [[ $current != "${old["$system"]}" ]]; then
        >&2 echo
        >&2 echo "*** WARNING: Three-way discrepancy."
        >&2 echo "*** Current config (being deployed): $new"
        >&2 echo "*** Last deployed config:            ${old["$system"]}"
        >&2 echo "*** Current *running* config:        $current"
        if [[ -t 0 ]] && [[ $force != "true" ]]; then
            read -n1 -rp "Proceed? [y/N] " yn
            if [[ $yn != [yY] ]]; then
                exit 0
            fi
            echo
        elif $force; then
            :
        else
            exit 1
        fi
    fi

    if "$force"; then
        >&2 echo
        >&2 echo "*** Forcing a redeploy of a NEW configuration for $system."
        >&2 echo
        # Even with -f, require interactive confirmation to deploy a new config.
        # This might be a mistake? If it gets annoying, remove it.
        if [ -t 0 ]; then
            read -n1 -rp "Continue with forced deploy? [y/N] " yn
            if [[ $yn = [yY] ]]; then
                rebuild switch --target-host "${target["$system"]}"
                >&2 echo
                >&2 echo "*** New result for $system: $(readlink result)"
            fi
        else
            exit 1
        fi
    else
        >&2 echo
        >&2 echo "*** This is a NEW configuration."

        if [ -t 0 ]; then
            read -n1 -rp "Show diff? [y/N] " yn
            if [[ $yn = [yY] ]]; then
                echo
                if ! nix-store --check-validity "$current" 2>/dev/null; then
                    >&2 echo "Fetching deployed system for diff..."
                    nix-copy-closure --from "${target["$system"]}" "$current"
                fi
                current_drv=$(nix-store --query --deriver "$current")
                if [[ -e $current_drv ]]; then
                    nix-diff --color always "$current_drv" "$(nix-store --query --deriver "$new")" | less
                else
                    >&2 echo "Derivation not available, falling back to nvd..."
                fi
                # Show it "finally", since it's short and interesting.
                nvd diff "$current" "$new"
            fi
        fi
        >&2 echo
        >&2 echo "*** New result for $system: $(readlink result)"
        >&2 echo "*** Edit redeploy_config.sh if you're satisfied with it, then rerun to deploy."
        exit 1
    fi
elif [[ $new = "$current" ]]; then
    echo "*** No change to system. Not deploying."
else
    rebuild switch --no-reexec --target-host "${target["$system"]}"
fi
