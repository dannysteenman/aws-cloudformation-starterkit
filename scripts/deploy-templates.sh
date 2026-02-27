#!/bin/bash
set -euo pipefail

show_help() {
    cat <<EOF
Usage: $0 -e <environment-name>

Deploys templates using the specified environment parameter configuration.

Options:
  -e, --environment <environment-name>  Specify the environment for which parameters should be used (e.g., 'production', 'test')
  -h, --help                            Display this help message and exit

Description:
This script will deploy all templates located in the 'templates' directory. If parameter configuration is required, it will attempt to find the corresponding parameter files in the 'parameters/<environment>' directory where the environment is specified by the -e or --environment option.

Example:
  $0 -e test
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates"
PARAMETERS_ROOT="$REPO_ROOT/parameters"

ENVIRONMENT=""
TEMPLATES=()

parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -e | --environment)
            if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" == "-" ]]; then
                die "Missing value for --environment (-e)."
            fi
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            show_help
            die "Unknown option $1"
            ;;
        esac
    done

    [[ -n "$ENVIRONMENT" ]] || die "--environment argument is required."
}

validate_inputs() {
    local parameters_dir="$1"

    [[ -d "$TEMPLATES_DIR" ]] || die "Templates directory '$TEMPLATES_DIR' not found."
    [[ -d "$parameters_dir" ]] || die "Parameters directory for environment '$ENVIRONMENT' not found at '$parameters_dir'."
}

collect_templates() {
    local templates_dir="$1"

    shopt -s nullglob
    TEMPLATES=("$templates_dir"/*.yml "$templates_dir"/*.yaml "$templates_dir"/*.json)
    shopt -u nullglob

    [[ ${#TEMPLATES[@]} -gt 0 ]] || die "No templates found in '$templates_dir'."
}

find_param_file() {
    local template_name="$1"
    local parameters_dir="$2"
    local ext candidate

    for ext in json yml yaml; do
        candidate="$parameters_dir/$template_name.$ext"
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
}

deploy_template() {
    local template="$1"
    local param_file="$2"
    local cmd

    cmd=(rain deploy "$template" --yes)
    if [[ -n "$param_file" ]]; then
        cmd+=(--config "$param_file")
    fi

    printf "Running command:"
    printf " %q" "${cmd[@]}"
    printf "\n"

    if "${cmd[@]}"; then
        echo "Deployment successful for $template"
        return 0
    fi

    echo "Deployment failed for $template" >&2
    return 1
}

main() {
    local parameters_dir failures template template_filename template_base param_file

    parse_args "$@"

    parameters_dir="$PARAMETERS_ROOT/$ENVIRONMENT"
    validate_inputs "$parameters_dir"
    collect_templates "$TEMPLATES_DIR"

    failures=0
    for template in "${TEMPLATES[@]}"; do
        echo "Deploying template: $template"

        template_filename="$(basename "$template")"
        template_base="${template_filename%.*}"
        param_file="$(find_param_file "$template_base" "$parameters_dir")"

        if ! deploy_template "$template" "$param_file"; then
            failures=$((failures + 1))
        fi
    done

    if [[ $failures -gt 0 ]]; then
        die "$failures deployment(s) failed."
    fi

    echo "All deployments completed."
}

main "$@"
