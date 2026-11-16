#!/bin/bash

# Delete IAM Users matching a username prefix, deactivating and removing
# their access keys first.
#
# Usage: ./delete-users.sh [--dry-run] [--yes] <username-prefix> [aws-args...]

set -o pipefail
set -o nounset
set -o errexit

DRY_RUN=false
ASSUME_YES=false
PREFIX=""
AWS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            ASSUME_YES=true
            shift
            ;;
        --*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "${PREFIX}" ]]; then
                PREFIX="$1"
            else
                # forward extra args to aws (e.g. --profile, --region)
                AWS_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

if [[ -z "${PREFIX}" ]]; then
    echo "Usage: $0 [--dry-run] [--yes] <username-prefix> [aws-args...]"
    echo ""
    echo "Args:"
    echo "  --dry-run          list matched users and their access keys, no changes"
    echo "  --yes              skip confirmation prompt"
    echo "  <username-prefix>  IAM users with UserName starting with this prefix"
    echo "  aws-args           extra args forwarded to aws cli (--profile x, ...)"
    exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "aws cli not found in PATH" >&2
    exit 1
fi

# List IAM users whose UserName starts with PREFIX
mapfile -t USERS < <(aws iam list-users --max-items 1000 \
    --output json \
    --query "Users[?starts_with(UserName, '${PREFIX}')].UserName" \
    "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" | jq -r .[])

if [[ ${#USERS[@]} -eq 0 || -z "${USERS[0]}" ]]; then
    echo "No IAM users found with prefix '${PREFIX}'."
    exit 0
fi

list_user_keys() {
    local user="$1"
    aws iam list-access-keys \
        --user-name "${user}" \
        --output text \
        --query "AccessKeyMetadata[].AccessKeyId" \
        "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" 2>/dev/null  || true
}

key_last_used() {
    local user="$1" key="$2"
    aws iam get-access-key-last-used \
        --access-key-id "${key}" \
        --output text \
        --query "AccessKeyLastUsed.LastUsedDate" \
        "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" 2>/dev/null || echo "n/a"
}

echo "Matched ${#USERS[@]} IAM user(s) with prefix '${PREFIX}':"
echo ""
printf "%-4s %-40s %-22s %s\n" "#" "UserName" "AccessKeys" "LastUsed"
idx=0
for user in "${USERS[@]}"; do
    idx=$((idx + 1))
    keys="$(list_user_keys "${user}" | tr '\n' ' ')"
    last_used=""
    for key in ${keys}; do
        lu="$(key_last_used "${user}" "${key}")"
        last_used="${lu} ${last_used}"
    done
    printf "%-4s %-40s %-22s %s\n" "${idx}" "${user}" "${keys:-none}" "${last_used:-n/a}"
    #break
done
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo "Dry run: no changes made."
    exit 0
fi

# Confirmation: batch prompt when multiple users, individual only when a single user
if [[ "${ASSUME_YES}" != true ]]; then
    if [[ ${#USERS[@]} -gt 1 ]]; then
        read -r -p "Delete ALL ${#USERS[@]} users listed above (deactivate/remove keys first)? [y/N] " answer
        case "${answer}" in
            [yY]|[yY][eE][sS]) ;;
            *)
                echo "Aborted."
                exit 0
                ;;
        esac
    else
        read -r -p "Delete user '${USERS[0]}' and its access keys? [y/N] " answer
        case "${answer}" in
            [yY]|[yY][eE][sS]) ;;
            *)
                echo "Aborted."
                exit 0
                ;;
        esac
    fi
fi

delete_user() {
    local user="$1"

    echo "--- ${user} ---"

    # Deactivate and delete access keys
    for key in $(list_user_keys "${user}"); do
        echo "  deactivating access key ${key}"
        aws iam update-access-key \
            --user-name "${user}" \
            --access-key-id "${key}" \
            --status Inactive \
            "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}"
        echo "  deleting access key ${key}"
        aws iam delete-access-key \
            --user-name "${user}" \
            --access-key-id "${key}" \
            "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}"
    done

    # Remove prerequisites that block iam:DeleteUser
    # (password login profile, group memberships, attached and inline policies)
    #aws iam delete-login-profile \
    #    --user-name "${user}" \
    #    "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" 2>/dev/null || true

    #for group in $(aws iam list-groups-for-user \
    #        --user-name "${user}" \
    #        --output text --query "Groups[].GroupName" \
    #        "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" 2>/dev/null); do
    #    echo "  removing from group ${group}"
    #    aws iam remove-user-from-group \
    #        --group-name "${group}" \
    #        --user-name "${user}" \
    #        "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}"
    #done

    for policy in $(aws iam list-attached-user-policies \
            --user-name "${user}" \
            --output text --query "AttachedPolicies[].PolicyArn" \
            "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" 2>/dev/null); do
        echo "  detaching policy ${policy}"
        aws iam detach-user-policy \
            --user-name "${user}" \
            --policy-arn "${policy}" \
            "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}"
    done

    for policy in $(aws iam list-user-policies \
            --user-name "${user}" \
            --output text --query "PolicyNames[]" \
            "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}" 2>/dev/null); do
        echo "  deleting inline policy ${policy}"
        aws iam delete-user-policy \
            --user-name "${user}" \
            --policy-name "${policy}" \
            "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}"
    done

    echo "  deleting user ${user}"
    aws iam delete-user \
        --user-name "${user}" \
        "${AWS_ARGS[@]+"${AWS_ARGS[@]}"}"

    echo "  done."
}

total=${#USERS[@]}
cnt=1
for user in "${USERS[@]}"; do
    echo "Deleting User ${user} ($cnt/$total)"
    delete_user "${user}"
    cnt=$((cnt + 1))
    #break
done

echo ""
echo "Deleted ${#USERS[@]} user(s) with prefix '${PREFIX}'."
