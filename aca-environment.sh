#!/bin/bash

# Manage the shared Azure resources used by code-server Container Apps.

set -euo pipefail

export AZURE_CORE_ONLY_SHOW_ERRORS="${AZURE_CORE_ONLY_SHOW_ERRORS:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CODE_SERVER_ACA_CONFIG:-${HOME}/.azure/code-server-aca.env}"
CONFIG_TEMPLATE="${SCRIPT_DIR}/docs/azure-container-apps.env.example"

usage() {
    cat <<'EOF'
Usage: ./aca-environment.sh [--config FILE] COMMAND [OPTIONS]

Commands:
  init                       Create a local deployment configuration
  create                     Create or validate the shared Azure resources
  publish [IMAGE] [--scaling-mode disabled|enabled]
                  [--min-replicas 0|1] [--cooldown-period SECONDS]
                             Build, verify and push an immutable image
  doctor                     Validate CLI access and shared Azure resources
  delete [--purge-local-state]
                             Delete the resource group after confirmation

IMAGE defaults to code-server-ol8.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

validate_scaling_values() {
    local mode="$1" min_replicas="$2" cooldown_period="$3"
    case "$mode" in
        disabled|enabled) ;;
        *) die "Invalid scaling mode '${mode}'; use disabled or enabled." ;;
    esac
    case "$min_replicas" in
        0|1) ;;
        *) die "Invalid min replicas '${min_replicas}'; use 0 or 1." ;;
    esac
    [[ "$cooldown_period" =~ ^[0-9]+$ ]] && [ "$cooldown_period" -le 2147483647 ] ||
        die "Invalid cooldown period '${cooldown_period}'; use 0-2147483647 seconds."
}

if [ "${1:-}" = "--config" ]; then
    [ "$#" -ge 3 ] || die "--config requires a file and a command."
    CONFIG_FILE="$2"
    shift 2
fi

COMMAND="${1:-}"
[ -n "$COMMAND" ] || {
    usage
    exit 1
}
shift

init_config() {
    local suffix config_dir temporary_config
    [ "$#" -eq 0 ] || die "init takes no arguments."
    [ ! -e "$CONFIG_FILE" ] || die "Config file already exists: ${CONFIG_FILE}"
    [ -f "$CONFIG_TEMPLATE" ] || die "Config template not found: ${CONFIG_TEMPLATE}"
    require_command openssl
    require_command sed
    require_command install

    suffix="$(openssl rand -hex 3)"
    config_dir="$(dirname "$CONFIG_FILE")"
    install -d -m 700 "$config_dir"
    temporary_config="$(mktemp "${config_dir}/.code-server-aca.env.XXXXXX")"
    trap 'rm -f "${temporary_config:-}"' RETURN
    sed "s/^SUFFIX=.*/SUFFIX=${suffix}/" "$CONFIG_TEMPLATE" > "$temporary_config"
    chmod 600 "$temporary_config"
    mv "$temporary_config" "$CONFIG_FILE"
    trap - RETURN
    printf 'Created config: %s\n' "$CONFIG_FILE"
}

load_config() {
    [ -f "$CONFIG_FILE" ] || die "Config file not found: ${CONFIG_FILE}; run init first."
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    : "${RESOURCE_GROUP:?RESOURCE_GROUP is required in ${CONFIG_FILE}}"
    : "${LOCATION:?LOCATION is required in ${CONFIG_FILE}}"
    : "${ENVIRONMENT_NAME:?ENVIRONMENT_NAME is required in ${CONFIG_FILE}}"
    : "${IDENTITY_NAME:?IDENTITY_NAME is required in ${CONFIG_FILE}}"
    : "${ACR_NAME:?ACR_NAME is required in ${CONFIG_FILE}}"
    : "${STORAGE_ACCOUNT:?STORAGE_ACCOUNT is required in ${CONFIG_FILE}}"
    : "${IMAGE_REPOSITORY:?IMAGE_REPOSITORY is required in ${CONFIG_FILE}}"
    PASSWORD_DIR="${PASSWORD_DIR:-${HOME}/.azure/code-server-aca/instances}"
    SCALING_MODE="${SCALING_MODE:-disabled}"
    SCALING_MIN_REPLICAS="${SCALING_MIN_REPLICAS:-0}"
    SCALING_COOLDOWN_PERIOD="${SCALING_COOLDOWN_PERIOD:-3600}"
}

tag_resource() {
    local resource_id="$1"
    az tag create --resource-id "$resource_id" --tags \
        application=code-server environment=production managed-by=aca-environment.sh -o none
}

create_environment() {
    local acr_id identity_id principal_id storage_id workspace_id
    [ "$#" -eq 0 ] || die "create takes no arguments."
    load_config
    require_command az

    for provider in Microsoft.App Microsoft.ContainerRegistry Microsoft.ManagedIdentity \
        Microsoft.OperationalInsights Microsoft.Storage; do
        az provider register --namespace "$provider" --wait -o none
    done

    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags \
        application=code-server environment=production managed-by=aca-environment.sh -o none

    if ! az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" >/dev/null 2>&1; then
        az acr create -g "$RESOURCE_GROUP" -n "$ACR_NAME" --sku Basic \
            --admin-enabled false --location "$LOCATION" --tags \
            application=code-server environment=production managed-by=aca-environment.sh -o none
    fi
    acr_id="$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query id -o tsv)"
    tag_resource "$acr_id"

    if ! az identity show -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" >/dev/null 2>&1; then
        az identity create -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" \
            --location "$LOCATION" --tags application=code-server environment=production \
            managed-by=aca-environment.sh -o none
    fi
    identity_id="$(az identity show -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" --query id -o tsv)"
    principal_id="$(az identity show -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" --query principalId -o tsv)"
    tag_resource "$identity_id"
    if [ "$(az role assignment list --assignee-object-id "$principal_id" --scope "$acr_id" \
        --query "[?roleDefinitionName=='AcrPull'] | length(@)" -o tsv)" = 0 ]; then
        az role assignment create --assignee-object-id "$principal_id" \
            --assignee-principal-type ServicePrincipal --role AcrPull --scope "$acr_id" -o none
    fi

    if ! az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" >/dev/null 2>&1; then
        az storage account create -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" \
            --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
            --https-only true --min-tls-version TLS1_2 --allow-blob-public-access false \
            --tags application=code-server environment=production \
            managed-by=aca-environment.sh -o none
    fi
    storage_id="$(az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" \
        --query id -o tsv)"
    tag_resource "$storage_id"

    if ! az containerapp env show -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" >/dev/null 2>&1; then
        az containerapp env create -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" \
            --location "$LOCATION" --tags application=code-server environment=production \
            managed-by=aca-environment.sh -o none
    fi
    tag_resource "$(az containerapp env show -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" \
        --query id -o tsv)"
    while IFS= read -r workspace_id; do
        [ -z "$workspace_id" ] || tag_resource "$workspace_id"
    done < <(az resource list -g "$RESOURCE_GROUP" \
        --resource-type Microsoft.OperationalInsights/workspaces --query '[].id' -o tsv)

    doctor_environment
}

doctor_environment() {
    local acr_server image_ref='<not-published>'
    load_config
    require_command az
    az account show --query '{subscription:name,subscriptionId:id,tenantId:tenantId}' -o table
    az group show -n "$RESOURCE_GROUP" --query '{name:name,state:properties.provisioningState,location:location}' -o table
    acr_server="$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query loginServer -o tsv)"
    az identity show -g "$RESOURCE_GROUP" -n "$IDENTITY_NAME" \
        --query '{name:name,principalId:principalId}' -o table
    az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" \
        --query '{name:name,state:provisioningState,location:location}' -o table
    az containerapp env show -g "$RESOURCE_GROUP" -n "$ENVIRONMENT_NAME" \
        --query '{name:name,state:properties.provisioningState,location:location}' -o table
    if [ -n "${IMAGE_TAG:-}" ] && [ "$IMAGE_TAG" != replace_with_immutable_tag ]; then
        az acr repository show -n "$ACR_NAME" \
            --image "${IMAGE_REPOSITORY}:${IMAGE_TAG}" >/dev/null
        image_ref="${acr_server}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    fi
    printf 'Registry: %s\nImage: %s\n' "$acr_server" "$image_ref"
}

publish_image() {
    local image=code-server-ol8 image_seen=false source_hash image_tag login_server remote_image
    local token config_dir temporary_config digest mode_arg='' min_arg='' cooldown_arg=''
    local mode min_replicas cooldown_period min_was_set=false cooldown_was_set=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --scaling-mode)
                [ "$#" -ge 2 ] || die "--scaling-mode requires disabled or enabled."
                mode_arg="$2"
                shift 2
                ;;
            --min-replicas)
                [ "$#" -ge 2 ] || die "--min-replicas requires 0 or 1."
                min_arg="$2"
                min_was_set=true
                shift 2
                ;;
            --cooldown-period)
                [ "$#" -ge 2 ] || die "--cooldown-period requires seconds."
                cooldown_arg="$2"
                cooldown_was_set=true
                shift 2
                ;;
            --*) die "Unknown publish option: $1" ;;
            *)
                [ "$image_seen" = false ] || die "publish accepts at most one image name."
                image="$1"
                image_seen=true
                shift
                ;;
        esac
    done
    load_config
    mode="${mode_arg:-$SCALING_MODE}"
    min_replicas="${min_arg:-$SCALING_MIN_REPLICAS}"
    cooldown_period="${cooldown_arg:-$SCALING_COOLDOWN_PERIOD}"
    validate_scaling_values "$mode" "$min_replicas" "$cooldown_period"
    if [ "$mode" = disabled ] && { [ "$min_was_set" = true ] || [ "$cooldown_was_set" = true ]; }; then
        die "--min-replicas and --cooldown-period require --scaling-mode enabled."
    fi
    if [ "$mode" = enabled ] && [ "$min_replicas" = 1 ]; then
        echo "Warning: scaling is enabled with min replicas 1; the App will not scale to zero." >&2
    fi
    require_command az
    require_command podman
    require_command tar
    require_command sha256sum
    require_command awk

    "${SCRIPT_DIR}/build-pod.sh"
    "${SCRIPT_DIR}/verify-defaults.sh" "$image"
    source_hash="$(tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 \
        --numeric-owner -cf - -C "$SCRIPT_DIR" src | sha256sum | cut -c1-12)"
    image_tag="$(date -u +%Y%m%d%H%M%S)-${source_hash}"
    login_server="$(az acr show -g "$RESOURCE_GROUP" -n "$ACR_NAME" --query loginServer -o tsv)"
    remote_image="${login_server}/${IMAGE_REPOSITORY}:${image_tag}"
    token="$(az acr login -n "$ACR_NAME" --expose-token --query accessToken -o tsv)"
    printf '%s' "$token" | podman login "$login_server" \
        --username 00000000-0000-0000-0000-000000000000 --password-stdin
    unset token
    podman tag "$image" "$remote_image"
    podman push "$remote_image"
    digest="$(az acr repository show -n "$ACR_NAME" \
        --image "${IMAGE_REPOSITORY}:${image_tag}" --query digest -o tsv)"

    config_dir="$(dirname "$CONFIG_FILE")"
    temporary_config="$(mktemp "${config_dir}/.code-server-aca.env.XXXXXX")"
    trap 'rm -f "${temporary_config:-}"' RETURN
    awk -v image_tag="$image_tag" -v mode="$mode" -v min_replicas="$min_replicas" \
        -v cooldown_period="$cooldown_period" '
        BEGIN { image_seen=mode_seen=min_seen=cooldown_seen=0 }
        /^IMAGE_TAG=/ { print "IMAGE_TAG=" image_tag; image_seen=1; next }
        /^SCALING_MODE=/ { print "SCALING_MODE=" mode; mode_seen=1; next }
        /^SCALING_MIN_REPLICAS=/ { print "SCALING_MIN_REPLICAS=" min_replicas; min_seen=1; next }
        /^SCALING_COOLDOWN_PERIOD=/ { print "SCALING_COOLDOWN_PERIOD=" cooldown_period; cooldown_seen=1; next }
        { print }
        END {
            if (!image_seen) print "IMAGE_TAG=" image_tag
            if (!mode_seen) print "SCALING_MODE=" mode
            if (!min_seen) print "SCALING_MIN_REPLICAS=" min_replicas
            if (!cooldown_seen) print "SCALING_COOLDOWN_PERIOD=" cooldown_period
        }
    ' "$CONFIG_FILE" > "$temporary_config"
    chmod 600 "$temporary_config"
    mv "$temporary_config" "$CONFIG_FILE"
    trap - RETURN
    if [ "$mode" = enabled ]; then
        printf 'Image: %s\nDigest: %s\nScaling: enabled (min=%s, max=1, cooldown=%ss)\nConfig: %s\n' \
            "$remote_image" "$digest" "$min_replicas" "$cooldown_period" "$CONFIG_FILE"
    else
        printf 'Image: %s\nDigest: %s\nScaling: disabled (min=1, max=1, cooldown=-)\nConfig: %s\n' \
            "$remote_image" "$digest" "$CONFIG_FILE"
    fi
}

delete_environment() {
    local purge_local_state=false confirmation
    if [ "${1:-}" = --purge-local-state ]; then
        purge_local_state=true
        shift
    fi
    [ "$#" -eq 0 ] || die "delete accepts only --purge-local-state."
    load_config
    require_command az
    az resource list -g "$RESOURCE_GROUP" --query '[].{name:name,type:type}' -o table
    echo "This permanently deletes the resource group and every Azure Files share it contains:" >&2
    printf '  Resource Group: %s\n' "$RESOURCE_GROUP" >&2
    [ "$purge_local_state" = false ] || printf '  Local state: %s and %s\n' \
        "$CONFIG_FILE" "$PASSWORD_DIR" >&2
    printf "Type '%s' to continue: " "$RESOURCE_GROUP" >&2
    IFS= read -r confirmation
    [ "$confirmation" = "$RESOURCE_GROUP" ] || die "Confirmation did not match; nothing was deleted."
    az group delete --name "$RESOURCE_GROUP" --yes
    if [ "$purge_local_state" = true ]; then
        [ -n "$PASSWORD_DIR" ] && [ "$PASSWORD_DIR" != / ] || die "Unsafe PASSWORD_DIR: ${PASSWORD_DIR}"
        rm -rf -- "$PASSWORD_DIR"
        rm -f -- "$CONFIG_FILE"
        echo 'Deleted local deployment config and instance passwords.'
    fi
    printf 'Deleted resource group: %s\n' "$RESOURCE_GROUP"
}

case "$COMMAND" in
    init) init_config "$@" ;;
    create) create_environment "$@" ;;
    publish) publish_image "$@" ;;
    doctor)
        [ "$#" -eq 0 ] || die "doctor takes no arguments."
        doctor_environment
        ;;
    delete) delete_environment "$@" ;;
    -h|--help|help)
        [ "$#" -eq 0 ] || die "help takes no arguments."
        usage
        ;;
    *)
        usage >&2
        die "Unknown command: ${COMMAND}"
        ;;
esac
