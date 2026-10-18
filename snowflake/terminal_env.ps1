# Load gitignored repo .env into this shell, then jump to sportsbook/.
# Used by Cursor/VS Code new terminals. Does not print secret values.
$repo = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repo ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or $line -notmatch "=") { return }
        $key, $value = $line.Split("=", 2)
        $name = $key.Trim()
        $raw = $value.Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $raw
    }
}
$defaultKey = Join-Path $env:USERPROFILE ".snowflake\dbt_cloud_rsa_key.p8"
if (-not $env:SNOWFLAKE_PRIVATE_KEY_PATH -and (Test-Path $defaultKey)) {
    $env:SNOWFLAKE_PRIVATE_KEY_PATH = $defaultKey
}
$sportsbook = Join-Path $repo "sportsbook"
Set-Location $sportsbook
$env:DBT_PROFILES_DIR = $sportsbook
