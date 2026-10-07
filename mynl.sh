#!/usr/bin/env bash
set -euo pipefail

project_definition="project-definition.json"

die() {
    echo "Error: $*" >&2
    exit 1
}

# Bash turns set -e off inside $(...), so config lookups in functions called that way
# (config, server_execute, service_name) exit explicitly with || exit 1.
config() {
    local value
    value=$(jq -r --arg profile "$profile" "$1" "$project_definition") || exit 1
    if [ "$value" = "null" ]; then
        die "$1 not found for profile '$profile' in $project_definition"
    fi
    echo "$value"
}

profile_config() {
    config ".profiles[\$profile].$1"
}

use_profile() {
    profile="$1"
    if ! jq -e --arg profile "$profile" '.profiles[$profile]' "$project_definition" > /dev/null; then
        die "Profile named '$profile' not found, to change profile try: export PROFILE=myprofile"
    fi
    echo "Executing with '$profile' profile"
}

echo_colorize() {
    local output="$1" esc=$'\e'
    output=${output//^0/${esc}[30m}
    output=${output//^1/${esc}[31m}
    output=${output//^2/${esc}[32m}
    output=${output//^3/${esc}[33m}
    output=${output//^4/${esc}[34m}
    output=${output//^5/${esc}[36m}
    output=${output//^6/${esc}[35m}
    output=${output//^7/${esc}[97m}
    output=${output//^8/${esc}[94m}
    output=${output//^9/${esc}[90m}
    echo "${output}${esc}[0m"
}

print_usage() {
    cat <<'EOF'
Control commands:
mynl connect                      Connects to the machine.
mynl deploy                       Syncs current content.
mynl restart                      Removes the docker stack and starts it again with restart.sh.
mynl stop                         Prints the last logs and removes the docker stack.
mynl logs follow                  Attaches to project log stream.
mynl logs [tail-lines]            Prints all or last n lines of logs.
mynl history [index=1]            Prints tail of 1=last shutdown instance, 2=second last.
mynl unpack                       Unpacks all iwd files and places them in iwds/ directory.
mynl pack                         Packs the unpacked iwd files.
mynl sync                         The one to rule them all - packs, deploys, restarts map or fully restarts if required.
mynl release-version <version>    Releases a new version by creating a branch from main, deploying, and setting up for public.
mynl finalize-version <version>   Finalizes development of a version by tagging and pushing the tag to the repository.

RCON commands:
mynl getstatus                    Gets public server status (without using rcon password).
mynl status                       Prints the status of the server.
mynl mapres                       Restarts the map on server.
mynl exec <command>               Performs given command on the server.

To change profile use 'export PROFILE=myprofile'
EOF
}

load_connection() {
    local user address
    user=$(config .connection.user)
    address=$(config .connection.address)
    ssh_key=$(config .connection.keyPath)
    ssh_target="$user@$address"
}

exec_ssh() {
    load_connection
    if [ "$1" = "-t" ]; then
        ssh -i "$ssh_key" -t "$ssh_target" "$2"
    else
        ssh -i "$ssh_key" "$ssh_target" "$1"
    fi
}

load_secrets() {
    # shellcheck source=/dev/null
    source ./secrets
    local rcon_password_var="${profile}_rcon_password" g_password_var="${profile}_g_password"
    rcon_password="${!rcon_password_var:-}"
    g_password="${!g_password_var:-}"

    if [ -z "$rcon_password" ]; then
        die "rcon_password not set for profile '$profile'."
    fi
    if [ -z "${rcon_password// /}" ]; then
        die "rcon_password is empty or contains only whitespace."
    fi
}

server_execute() {
    local cmd="$1" address port obfuscated_cmd response
    address=$(config .connection.address) || exit 1
    port=$(profile_config cod2.port) || exit 1
    obfuscated_cmd=$(echo "$cmd" | perl -pe 's/(rcon) (\w+) (.+)/\1 ***** \3/g')
    echo "Executing command '$obfuscated_cmd' for server $address:$port." >&2

    # nc fails when the server is down; callers treat an empty response as offline
    response=$(printf '\377\377\377\377%s' "$cmd" \
        | nc -u -w 2 "$address" "$port" \
        | perl -pe 's/\xff{4}print//g' \
        | LC_ALL=C tr -cd '\11\12\15\40-\176') || true
    echo "$response"
}

rcon_execute() {
    load_secrets
    server_execute "rcon $rcon_password $1"
}

info_value() {
    awk -F "\\\\" -v key="$1" '{for (i=1; i<=NF; i++) if ($i == key) print $(i+1)}'
}

sed_in_place() {
    sed -i.sed-bak "$1" "$2"
    rm "$2.sed-bak"
}

write_server_cfg() {
    local cfg_file="$1" cfg_path="src/nl/$1"
    if [ -z "$cfg_file" ]; then
        return
    fi
    cp "$cfg_path" "$cfg_file.bak"

    if [ "$g_password" != " " ]; then
        echo "Setting g_password"
        sed_in_place "s/set g_password \".*\"/set g_password \"$g_password\"/" "$cfg_path"
    else
        echo "Clearing g_password"
        sed_in_place 's/set g_password ".*"/set g_password ""/' "$cfg_path"
    fi

    echo "Setting rcon_password"
    sed_in_place "s/set rcon_password \".*\"/set rcon_password \"$rcon_password\"/" "$cfg_path"
}

restore_server_cfg() {
    local cfg_file="$1"
    if [ -z "$cfg_file" ]; then
        return
    fi
    cp "$cfg_file.bak" "src/nl/$cfg_file"
    rm "$cfg_file.bak"
}

service_name() {
    local project
    project=$(profile_config containerName) || exit 1
    echo "${project}_${project}"
}

connect() {
    local address remote_path
    address=$(config .connection.address)
    remote_path=$(profile_config remoteDeploymentPath)
    echo "Connecting to $address SSH"
    exec_ssh -t "cd $remote_path ; bash --login"
}

deploy() {
    local remote_path local_path excludes exclude cfg_file rsync_options rsync_status=0
    load_connection
    remote_path=$(profile_config remoteDeploymentPath)
    local_path=$(profile_config localDeploymentPath)
    excludes=$(profile_config 'rsyncExclude // [] | .[]')
    cfg_file=$(profile_config 'cod2.cfgFile // ""')
    load_secrets

    rsync_options=(-az -e "ssh -i $ssh_key" --progress --delete)
    while IFS= read -r exclude; do
        if [ -n "$exclude" ]; then
            rsync_options+=("--exclude=$exclude")
        fi
    done <<< "$excludes"

    write_server_cfg "$cfg_file"
    (cd "$local_path" && rsync "${rsync_options[@]}" ./* "$ssh_target:$remote_path") || rsync_status=$?
    restore_server_cfg "$cfg_file"
    if [ "$rsync_status" -ne 0 ]; then
        exit "$rsync_status"
    fi

    announce "^8[UPDATE] ^7Mod version updated"
}

announce() {
    local port
    port=$(profile_config 'cod2.port // ""')
    if [ -z "$port" ]; then
        echo "Skipping announcement - no cod2 port found"
        return
    fi
    rcon_execute "say $1" > /dev/null
}

restart() {
    local restart_path restart_docker_compose project
    restart_path=$(profile_config restartPath)
    restart_docker_compose=$(profile_config restartDockerCompose)
    project=$(profile_config containerName)

    announce "^8[UPDATE] ^7Server restart dispatched, please use ^3/reconnect"
    exec_ssh "$(cat <<EOF
cd $restart_path || exit 1
echo 'Removing stack $project...'
docker stack rm --detach=false $project || echo 'Failed to remove stack'
./restart.sh $restart_docker_compose
EOF
)"
}

stop() {
    local project service
    project=$(profile_config containerName)
    service=$(service_name)

    announce "^8[UPDATE] ^9Server is ^7stopping"
    exec_ssh "$(cat <<EOF
container_id=\$(docker ps -q --filter label=com.docker.swarm.service.name=$service | head -n 1)
if [ -n "\$container_id" ]; then
    docker logs --tail 500 "\$container_id"
else
    echo 'No running container'
fi
echo 'Executing docker stack rm...'
docker stack rm $project
EOF
)"
}

show_logs() {
    local mode="$1" logs_options="" service remote_command
    if [ "$mode" = "follow" ]; then
        logs_options="-f"
    elif [[ $mode =~ ^[0-9]+$ ]]; then
        logs_options="--tail $mode"
    fi

    service=$(service_name)
    remote_command=$(cat <<EOF
container_id=\$(docker ps -q --filter label=com.docker.swarm.service.name=$service | head -n 1)
if [ -n "\$container_id" ]; then
    docker logs $logs_options "\$container_id"
else
    echo 'Warning: Container not found - printing service logs'
    docker service logs $logs_options $service --raw
fi
EOF
)
    if [ "$mode" = "follow" ]; then
        exec_ssh -t "$remote_command"
    else
        exec_ssh "$remote_command"
    fi
}

show_history() {
    local index="$1" service
    if ! [[ $index =~ ^[1-9][0-9]*$ ]]; then
        die "Argument must be a positive number"
    fi
    service=$(service_name)

    exec_ssh "$(cat <<EOF
container_id=\$(docker ps -a -q --filter label=com.docker.swarm.service.name=$service --filter status=exited | sed -n '${index}p')
if [ -z "\$container_id" ]; then
    echo 'Error: No stopped container number $index for $service' >&2
    exit 1
fi
echo "container_id=\$container_id"
docker logs --tail 200 "\$container_id"
EOF
)"
}

getstatus() {
    local response current_map hostname players_list player_count player player_score player_name
    response=$(server_execute "getstatus")

    current_map=$(echo "$response" | info_value mapname)
    hostname=$(echo "$response" | info_value sv_hostname)
    players_list=$(echo "$response" | awk '/^[0-9]+ /')
    player_count=$(echo "$players_list" | awk 'NF {n++} END {print n+0}')

    if [ -z "$current_map" ] || [ -z "$hostname" ]; then
        die "Could not retrieve the required information from the CoD2 server."
    fi

    echo "-------------------"
    echo_colorize "$hostname ^7playing ^3$current_map^7, with ^3$player_count ^7players:"
    if [ -z "$players_list" ]; then
        return
    fi
    while read -r player; do
        player_score=$(echo "$player" | cut -d' ' -f1)
        player_name=$(echo "$player" | cut -d' ' -f3- | tr -d '"')
        echo_colorize "Name: $player_name ^7| Score: ^2$player_score"
    done <<< "$players_list"
}

unpack() {
    local iwds_path iwd_file target_folder
    iwds_path=$(profile_config cod2.iwdsPath)

    if [ -d iwds ]; then
        die "The iwds directory exists. Firstly remove it or pack using 'mynl pack'."
    fi

    echo "Unpacking iwd files from '$iwds_path' to 'iwds' directory"
    for iwd_file in "$iwds_path"/*.iwd; do
        if [ ! -f "$iwd_file" ]; then
            die "No iwd files found in '$iwds_path'."
        fi
        target_folder="iwds/$(basename "$iwd_file")/all"
        mkdir -p "$target_folder"
        unzip -q "$iwd_file" -d "$target_folder"
        echo "Unpacked: $iwd_file"
    done
}

pack() {
    local iwds_path iwd_folder iwd_name iwd_path temp_dir subfolder entry tmp_iwd_path
    iwds_path=$(profile_config cod2.iwdsPath)

    echo "Packing directories from 'iwds' to '$iwds_path' iwd files"
    shopt -s nullglob
    for iwd_folder in iwds/*.iwd/; do
        iwd_name=$(basename "$iwd_folder")
        iwd_path="$iwds_path/$iwd_name"
        temp_dir="iwds/$iwd_name.temp"
        mkdir -p "$temp_dir"

        for subfolder in "$iwd_folder"*/; do
            for entry in "$subfolder"*; do
                cp -R "$entry" "$temp_dir/"
            done
        done

        tmp_iwd_path="$(realpath iwds)/$iwd_name.tmp"
        find "$temp_dir" -type f -exec touch -t 202201010000.00 {} +
        (cd "$temp_dir" && find . -type f \! -name ".DS_Store" | sort | zip -q -X -r -@ "$tmp_iwd_path")
        rm -rf "$temp_dir"

        if cmp -s "$tmp_iwd_path" "$iwd_path"; then
            rm "$tmp_iwd_path"
            echo "Unchanged: $iwd_path"
        else
            mv "$tmp_iwd_path" "$iwd_path"
            echo "Packed: $iwd_path"
        fi
    done
    shopt -u nullglob
}

sync_server() {
    local hostname
    hostname=$(server_execute "getstatus" | info_value sv_hostname)

    pack
    deploy

    if [ -n "$hostname" ]; then
        rcon_execute "map_restart"
        show_logs follow
    else
        restart
    fi
}

finalize_version() {
    local version="$1"
    if [ -z "$version" ]; then
        die "Version number required to finalize."
    fi
    git checkout "version/$version"
    git pull
    git tag "$version"
    git push --tags
    echo "Finalized version $version and pushed tags to remote."
}

release_version() {
    local new_version="$1"
    if [ -z "$new_version" ]; then
        die "New version number required to release."
    fi
    git checkout main
    git pull
    git checkout -b "version/$new_version"
    git push -u origin "version/$new_version"
    pack
    use_profile public
    deploy
    echo "Released $new_version to the public server."
}

command="${1:-}"
case "$command" in
    "")
        print_usage
        die "Missing verb"
        ;;
    connect | deploy | restart | stop | logs | history | status | getstatus | mapres | exec | unpack | pack | sync | finalize-version | release-version) ;;
    *)
        print_usage
        die "Invalid verb '$command'"
        ;;
esac

if [ ! -f "$project_definition" ]; then
    die "$project_definition doesn't exist. Please use mynl CLI tool from within NL directory."
fi
use_profile "${PROFILE:-default}"

case "$command" in
    connect) connect ;;
    deploy) deploy ;;
    restart) restart ;;
    stop) stop ;;
    logs) show_logs "${2:-}" ;;
    history) show_history "${2:-1}" ;;
    status) rcon_execute "status" ;;
    getstatus) getstatus ;;
    mapres) rcon_execute "map_restart" ;;
    exec) rcon_execute "${*:2}" ;;
    unpack) unpack ;;
    pack) pack ;;
    sync) sync_server ;;
    finalize-version) finalize_version "${2:-}" ;;
    release-version) release_version "${2:-}" ;;
esac
