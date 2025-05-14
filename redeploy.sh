# Usage:
#        ./redeploy.sh <system>

# Redeploys a server. Enforces that the last-deployed state is recorded in
# redeploy_config.sh. This might be more pain than it's worth, but the idea was
# to keep track of deployment conflicts since there are multiple people who do
# them. Better ideas welcome.

# Since this deploys to a remote server, /etc/nixos is unused on that server.

# Must be defined in redeploy_config.sh
declare -A target old nixos_rebuild_args

# shellcheck disable=SC1091
. redeploy_config.sh

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
current_drv=$(ssh "${target["$system"]}" nix-store --query --deriver "$current")

if [[ $current != "${old["$system"]}" ]]; then
    >&2 echo
    >&2 echo "*** WARNING: The last deployed system is not the same as the current running system."
    >&2 echo "*** Last deployed system: ${old["$system"]}"
    >&2 echo "*** Current system: $current"
    if [ -t 0 ]; then
        read -n1 -rep "Proceed? [y/N] " yn
        if [[ $yn != [yY] ]]; then
            exit 0
        fi
    else
        exit 1
    fi
fi

if [[ ${old["$system"]} != "$new" ]]; then
    if [[ "${1:-}" = '-f' ]]; then
        >&2 echo
        >&2 echo "*** Forcing a redeploy of a NEW configuration for $system."
        >&2 echo
        rebuild switch --target-host "${target["$system"]}"
        >&2 echo
        >&2 echo "*** New result for $system: $(readlink result)"
    else
        >&2 echo
        >&2 echo "*** This is a NEW configuration. Edit redeploy_config.sh if you're satisfied with it."

        if [ -t 0 ]; then
            read -rp "Show diff? [y/N] " yn
            if [[ $yn = [yY] ]]; then
                nix copy --substitute-on-destination --from ssh://"${target["$system"]}" "$current_drv"
                nix-diff --color always "${old["$system"]}" "$new" | less
            fi
        fi
        >&2 echo
        >&2 echo "*** New result for $system: $(readlink result)"
        exit 1
    fi
elif [[ $new = "$current" ]]; then
    echo "*** No change to system. Not deploying."
else
    rebuild switch --fast --target-host "${target["$system"]}"
fi
