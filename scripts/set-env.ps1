# Sets the environment variables dbt needs for the current PowerShell session.
# Usage (from the repo root):   .\scripts\set-env.ps1 -TargetEnv dev
# No account ID is stored anywhere: it is read from your current AWS login.
param(
    [ValidateSet("dev", "prod")]
    [string]$TargetEnv = "dev"
)

$account = (aws sts get-caller-identity --query Account --output text).Trim()

$env:DBT_ENV = $TargetEnv
$env:ATHENA_RESULTS_BUCKET = "zaki-lakehouse-dbt-$TargetEnv-athena-results-$account"
$env:LAKEHOUSE_BUCKET = "zaki-lakehouse-dbt-$TargetEnv-lakehouse-$account"
$env:AWS_DEFAULT_REGION = "eu-west-2"

Write-Host "Environment variables set for '$TargetEnv'. Now run: cd dbt; dbt build"
