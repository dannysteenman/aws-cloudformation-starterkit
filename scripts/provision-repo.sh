#!/bin/bash

# Function to prompt the user for input and validate environment selection
prompt_for_environment() {
    PS3="Please enter your environment choice: "
    select env in "test" "staging" "production"; do
        if [[ -n $env ]]; then
            echo $env
            break
        else
            echo "Invalid choice. Please select a valid environment."
        fi
    done
}

# Prompt the user for input
read -p "Enter the GitHub repository name (e.g., dannysteenman/aws-cloudformation-starterkit): " repo_name
environment=$(prompt_for_environment)

# Convert environment to uppercase
uppercase_env=$(echo "$environment" | tr 'a-z' 'A-Z')

# Derive filenames and directories
workflow_dir=".github/workflows"
workflow_filename="${workflow_dir}/cloudformation-deploy-${environment}.yml"
parameters_dir="parameters/${environment}"
oidc_provider_file="${parameters_dir}/oidc-provider.yml"

# Create the .github/workflows directory if it does not exist
mkdir -p "$workflow_dir"

# Create the GitHub workflow file with dynamic content
cat <<EOL >"$workflow_filename"
name: Deploy CloudFormation Templates to ${environment} Account
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
          role-to-assume: arn:aws:iam::\${{ vars.${uppercase_env}_AWS_ACCOUNT_ID }}:role/GitHubActionsServiceRole
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
        run: ./scripts/deploy-templates.sh
EOL

# Create the parameters directory if it does not exist
mkdir -p "$parameters_dir"

# Create the oidc-provider.yml file with dynamic content
cat <<EOL >"$oidc_provider_file"
Parameters:
  # Set subjectclaimfilter to your own repo here to allow github actions to assume the role on your AWS account
  SubjectClaimFilters: "repo:${repo_name}:*"
Tags:
  Project: GitHubActions
EOL

echo "Provisioning completed. Workflow file '$workflow_filename' and parameters file '$oidc_provider_file' have been created."
