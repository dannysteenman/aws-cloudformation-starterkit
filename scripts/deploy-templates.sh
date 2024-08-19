#!/bin/bash

# Function to display help message
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

# Check if no arguments were provided
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# Parse arguments
ENVIRONMENT=""
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -e | --environment)
        ENVIRONMENT="$2"
        shift # past argument
        shift # past value
        ;;
    -h | --help)
        show_help
        exit 0
        ;;
    *)
        echo "Unknown option $1"
        show_help
        exit 1
        ;;
    esac
done

# Validate environment argument
if [ -z "$ENVIRONMENT" ]; then
    echo "Error: --environment argument is required."
    show_help
    exit 1
fi

# Set the path to the templates and parameters directories
TEMPLATES_DIR="templates"
PARAMETERS_DIR="parameters/$ENVIRONMENT"

# Check if the templates directory exists
if [ ! -d "$TEMPLATES_DIR" ]; then
    echo "Error: Templates directory '$TEMPLATES_DIR' not found."
    exit 1
fi

# Check if the parameters directory for the environment exists
if [ ! -d "$PARAMETERS_DIR" ]; then
    echo "Error: Parameters directory for environment '$ENVIRONMENT' not found."
    exit 1
fi

# Loop through all YAML/YML/JSON files in the templates directory
for template in "$TEMPLATES_DIR"/*.{yml,yaml,json}; do
    # Check if the file exists (to handle the case when no matching files are found)
    if [ -e "$template" ]; then
        echo "Deploying template: $template"

        # Construct the base name of the template without its extension
        basename=$(basename "$template")
        name_without_extension="${basename%.*}"

        # Attempt to find the parameter file with different extensions
        found_param_file=false
        for ext in json yml yaml; do
            param_file="$PARAMETERS_DIR/$name_without_extension.$ext"
            if [ -e "$param_file" ]; then
                found_param_file=true
                break
            fi
        done

        # Determine the command to run based on whether a parameter file was found
        if [ "$found_param_file" = true ]; then
            rain_command="rain deploy \"$template\" --yes --config \"$param_file\""
        else
            rain_command="rain deploy \"$template\" --yes"
        fi

        # Show the command being run
        echo "Running command: $rain_command"

        # Run the determined command
        output=$(eval "$rain_command" 2>&1)
        deployment_status=$?

        # Log the output
        if [ $deployment_status -eq 0 ]; then
            echo "Deployment successful for $template"
        else
            echo "Deployment failed for $template"
            echo "Deployment output:"
            echo "$output"
            echo "-----------------------------------"
        fi
    fi
done

echo "All deployments completed."

echo "All deployments completed."
