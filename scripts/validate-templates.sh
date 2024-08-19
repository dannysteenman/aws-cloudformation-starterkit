#!/bin/bash

# Define the directory containing CloudFormation templates
TEMPLATE_DIR="./templates"
CONFIG_FILE="./.checkov.yml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"         # Get the script directory
REQUIREMENTS_FILE="$SCRIPT_DIR/../requirements.txt" # Adjust path relative to script location

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Python is installed
if ! command_exists python3; then
    echo "Python3 is not installed. Please install Python3 to proceed."
    exit 1
fi

# Check if pip is installed
if ! command_exists pip3; then
    echo "pip3 is not installed. Please install pip3 to proceed."
    exit 1
fi

# Check if Checkov is installed, install if not
if ! command_exists checkov; then
    echo "Checkov is not installed. Installing Checkov..."
    pip3 install -r "$REQUIREMENTS_FILE"
    if [ $? -ne 0 ]; then
        echo "Failed to install Checkov. Please check your Python and pip installation."
        exit 1
    fi
else
    echo "Checkov is already installed."
fi

# Validate CloudFormation templates using Checkov
echo "Validating CloudFormation templates in $TEMPLATE_DIR... using the configuration file $CONFIG_FILE"
checkov

# Check the exit status of Checkov
if [ $? -eq 0 ]; then
    echo "Validation completed successfully. No issues found."
else
    echo "Validation completed with issues. Please review the output above."
fi
