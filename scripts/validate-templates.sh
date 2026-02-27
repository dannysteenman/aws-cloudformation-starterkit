#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-$ROOT_DIR/templates}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/.checkov.yml}"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-$ROOT_DIR/requirements.txt}"
DEFAULT_TOOLS_VENV_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/aws-cloudformation-starter-kit-tools-venv"
TOOLS_VENV_DIR="${TOOLS_VENV_DIR:-$DEFAULT_TOOLS_VENV_DIR}"
CHECKOV_CMD=()

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 is required but not installed."
        exit 1
    fi
}

validate_paths() {
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        echo "Template directory not found: $TEMPLATE_DIR"
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Checkov config file not found: $CONFIG_FILE"
        exit 1
    fi
}

ensure_checkov() {
    require_command python3

    if ! python3 -m pip --version >/dev/null 2>&1; then
        echo "Python3 pip module is required but was not found."
        exit 1
    fi

    if command -v checkov >/dev/null 2>&1; then
        echo "Checkov is already installed."
        CHECKOV_CMD=("checkov")
        return
    fi

    if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
        echo "Requirements file not found: $REQUIREMENTS_FILE"
        exit 1
    fi

    local venv_python="$TOOLS_VENV_DIR/bin/python3"
    local venv_checkov="$TOOLS_VENV_DIR/bin/checkov"

    if [[ ! -x "$venv_python" ]]; then
        echo "Checkov is not installed. Creating tool virtualenv at $TOOLS_VENV_DIR..."
        if ! python3 -m venv "$TOOLS_VENV_DIR"; then
            echo "Failed to create virtualenv at $TOOLS_VENV_DIR."
            exit 1
        fi
    fi

    echo "Installing validation dependencies from $REQUIREMENTS_FILE into $TOOLS_VENV_DIR..."
    if ! "$venv_python" -m pip install -r "$REQUIREMENTS_FILE"; then
        echo "Failed to install Checkov dependencies into $TOOLS_VENV_DIR."
        exit 1
    fi

    if [[ ! -x "$venv_checkov" ]]; then
        echo "Checkov was not found after installation: $venv_checkov"
        exit 1
    fi

    CHECKOV_CMD=("$venv_checkov")
}

run_validation() {
    echo "Validating CloudFormation templates in $TEMPLATE_DIR using $CONFIG_FILE"

    if "${CHECKOV_CMD[@]}" --directory "$TEMPLATE_DIR" --config-file "$CONFIG_FILE"; then
        echo "Validation completed successfully. No issues found."
        return 0
    fi

    echo "Validation completed with issues. Please review the output above."
    return 1
}

main() {
    validate_paths
    ensure_checkov
    run_validation
}

main "$@"
