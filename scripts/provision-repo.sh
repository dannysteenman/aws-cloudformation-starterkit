#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

VALID_ENVIRONMENTS=("test" "staging" "production")

REPO_NAME=""
ENVIRONMENT=""
UPPERCASE_ENV=""
WORKFLOW_DIR=""
WORKFLOW_FILENAME=""
PARAMETERS_DIR=""
OIDC_PROVIDER_FILE=""

show_help() {
    cat <<EOF
Usage: $0 [-r <owner/repo>] [-e <environment>]

Provision GitHub workflow and OIDC parameter files for a repository.

Options:
  -r, --repo <owner/repo>    GitHub repository name (for example: towardsthecloud/aws-cloudformation-starter-kit)
  -e, --environment <env>    Environment name: test, staging, or production
  -h, --help                 Show this help message and exit

If -r or -e are omitted, this script prompts for the missing values in interactive mode.
EOF
}

error() {
    printf 'Error: %s\n' "$*" >&2
}

on_error() {
    local line="$1"
    local exit_code="$2"
    printf 'Error: provision-repo.sh failed at line %s (exit code: %s)\n' "$line" "$exit_code" >&2
}

trap 'on_error "$LINENO" "$?"' ERR

ensure_dependencies() {
    local dep
    for dep in cat mkdir; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            error "Required command '$dep' is not available."
            exit 1
        fi
    done
}

validate_repo_name() {
    local repo_name="$1"
    if [[ ! "$repo_name" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        error "Invalid repository format '$repo_name'. Expected '<owner>/<repo>' with letters, numbers, '.', '_', or '-'."
        return 1
    fi
}

validate_environment() {
    local environment="$1"
    local supported_environments=""
    local valid_environment
    for valid_environment in "${VALID_ENVIRONMENTS[@]}"; do
        if [[ "$environment" == "$valid_environment" ]]; then
            return 0
        fi
    done
    supported_environments=$(printf '%s, ' "${VALID_ENVIRONMENTS[@]}")
    supported_environments=${supported_environments%, }
    error "Invalid environment '$environment'. Expected one of: ${supported_environments}."
    return 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -r | --repo)
            if [[ $# -lt 2 ]]; then
                error "Missing value for '$1'."
                show_help >&2
                exit 1
            fi
            REPO_NAME="$2"
            shift 2
            ;;
        -e | --environment)
            if [[ $# -lt 2 ]]; then
                error "Missing value for '$1'."
                show_help >&2
                exit 1
            fi
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option '$1'."
            show_help >&2
            exit 1
            ;;
        esac
    done
}

prompt_for_repo_name() {
    local repo_input=""
    while true; do
        read -r -p "Enter the GitHub repository name (e.g., towardsthecloud/aws-cloudformation-starter-kit): " repo_input
        if validate_repo_name "$repo_input"; then
            printf '%s\n' "$repo_input"
            return 0
        fi
    done
}

prompt_for_environment() {
    local environment_choice=""
    PS3="Please enter your environment choice: "
    select environment_choice in "${VALID_ENVIRONMENTS[@]}"; do
        if [[ -n "$environment_choice" ]]; then
            printf '%s\n' "$environment_choice"
            return 0
        fi
        printf 'Invalid choice. Please select a valid environment.\n' >&2
    done
}

resolve_inputs() {
    if [[ -z "$REPO_NAME" ]]; then
        if [[ -t 0 ]]; then
            REPO_NAME="$(prompt_for_repo_name)"
        else
            error "Repository name is required in non-interactive mode. Use -r or --repo."
            exit 1
        fi
    fi
    if ! validate_repo_name "$REPO_NAME"; then
        exit 1
    fi

    if [[ -z "$ENVIRONMENT" ]]; then
        if [[ -t 0 ]]; then
            ENVIRONMENT="$(prompt_for_environment)"
        else
            error "Environment is required in non-interactive mode. Use -e or --environment."
            exit 1
        fi
    fi
    if ! validate_environment "$ENVIRONMENT"; then
        exit 1
    fi
}

derive_paths() {
    UPPERCASE_ENV=${ENVIRONMENT^^}
    WORKFLOW_DIR=".github/workflows"
    WORKFLOW_FILENAME="${WORKFLOW_DIR}/cloudformation-deploy-${ENVIRONMENT}.yml"
    PARAMETERS_DIR="parameters/${ENVIRONMENT}"
    OIDC_PROVIDER_FILE="${PARAMETERS_DIR}/oidc-provider.yml"
}

write_workflow_file() {
    mkdir -p "$WORKFLOW_DIR"
    cat <<EOF >"$WORKFLOW_FILENAME"
name: Deploy CloudFormation Templates to ${ENVIRONMENT} Account
on:
  push:
    branches: [main]
permissions:
  id-token: write
  contents: read
  security-events: write
  actions: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::\${{ vars.${UPPERCASE_ENV}_AWS_ACCOUNT_ID }}:role/GitHubActionsServiceRole
          aws-region: \${{ vars.AWS_REGION }}
      - name: Install Rain
        run: |
          RAIN_VERSION=\$(curl -s https://api.github.com/repos/aws-cloudformation/rain/releases/latest | jq -r .tag_name)
          curl -L -o rain.zip "https://github.com/aws-cloudformation/rain/releases/download/\${RAIN_VERSION}/rain-\${RAIN_VERSION}_linux-amd64.zip"
          unzip rain.zip
          chmod +x rain-\${RAIN_VERSION}_linux-amd64/rain
          sudo mv rain-\${RAIN_VERSION}_linux-amd64/rain /usr/local/bin/
          rm -rf rain-\${RAIN_VERSION}_linux-amd64 rain.zip
          rain --version
      - name: Checkov GitHub Action
        uses: bridgecrewio/checkov-action@v12
        with:
          config_file: .checkov.yml
      - name: Deploy CloudFormation templates
        run: ./scripts/deploy-templates.sh -e ${ENVIRONMENT}
EOF
}

write_oidc_provider_file() {
    mkdir -p "$PARAMETERS_DIR"
    cat <<EOF >"$OIDC_PROVIDER_FILE"
Parameters:
  # Set subjectclaimfilter to your own repo here to allow github actions to assume the role on your AWS account
  SubjectClaimFilters: "repo:${REPO_NAME}:*"
Tags:
  Project: GitHubActions
EOF
}

main() {
    ensure_dependencies
    parse_args "$@"
    resolve_inputs
    derive_paths
    write_workflow_file
    write_oidc_provider_file

    printf "Provisioning completed. Workflow file '%s' and parameters file '%s' have been created.\n" \
        "$WORKFLOW_FILENAME" "$OIDC_PROVIDER_FILE"
}

main "$@"
