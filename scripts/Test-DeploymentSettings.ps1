<#
.SYNOPSIS
    Validates a deployment settings file against the solution it will be used with.

.DESCRIPTION
    Fails before the import starts when the settings file would leave the
    solution half-configured. An import with a missing or invalid connection
    reference does succeed, but every flow that depends on it is left turned
    off, and that is usually discovered by a user rather than by the pipeline.

    Errors:
      - a connection reference in the solution is missing from the file
      - a ConnectionId is empty or still the all-zero placeholder
      - the file is not valid JSON

    Warnings:
      - an environment variable has no value (Dataverse falls back to the
        default value defined in the solution)
      - the file contains entries the solution does not have

.PARAMETER SettingsFile
    Path to the deployment settings JSON file.

.PARAMETER SolutionZip
    Path to the packed solution that will be imported.

.PARAMETER SolutionFolder
    Path to an unpacked solution root. Use instead of -SolutionZip.

.EXAMPLE
    ./scripts/Test-DeploymentSettings.ps1 -SettingsFile deployment-settings/prod.json `
        -SolutionZip out/CoreCustomizations_managed.zip

.NOTES
    Requires the Power Platform CLI (pac) on PATH.
#>
#Requires -Version 7.0

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'GitHub workflow commands (::error::) must go to stdout and must not end up in the pipeline output.')]
[CmdletBinding(DefaultParameterSetName = 'Zip')]
param(
    [Parameter(Mandatory)]
    [string] $SettingsFile,

    [Parameter(Mandatory, ParameterSetName = 'Zip')]
    [string] $SolutionZip,

    [Parameter(Mandatory, ParameterSetName = 'Folder')]
    [string] $SolutionFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Finding {
    param([ValidateSet('error', 'warning')] [string] $Level, [string] $Message)
    if ($env:GITHUB_ACTIONS -eq 'true') {
        Write-Host "::$Level file=$SettingsFile::$Message"
    }
    elseif ($Level -eq 'error') {
        Write-Host "ERROR: $Message" -ForegroundColor Red
    }
    else {
        Write-Warning $Message
    }
}

try {
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
}
catch {
    throw "Settings file '$SettingsFile' is not valid JSON: $($_.Exception.Message)"
}

$expectedFile = Join-Path ([System.IO.Path]::GetTempPath()) "expected-$([guid]::NewGuid()).json"
try {
    $source = if ($PSCmdlet.ParameterSetName -eq 'Zip') { @('--solution-zip', $SolutionZip) } else { @('--solution-folder', $SolutionFolder) }
    $pacOutput = & pac solution create-settings @source --settings-file $expectedFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "pac solution create-settings failed:`n$($pacOutput -join "`n")"
    }
    $expected = Get-Content $expectedFile -Raw | ConvertFrom-Json
}
finally {
    Remove-Item $expectedFile -ErrorAction SilentlyContinue
}

$errors = 0
$zeroGuid = [guid]::Empty.ToString()

$actualRefs = @{}
foreach ($r in @($settings.ConnectionReferences) | Where-Object { $_ }) { $actualRefs[$r.LogicalName] = $r }
foreach ($r in @($expected.ConnectionReferences) | Where-Object { $_ }) {
    if (-not $actualRefs.ContainsKey($r.LogicalName)) {
        Write-Finding error "Connection reference '$($r.LogicalName)' is missing."
        $errors++
        continue
    }
    $id = [string] $actualRefs[$r.LogicalName].ConnectionId
    if ([string]::IsNullOrWhiteSpace($id) -or $id -eq $zeroGuid) {
        Write-Finding error "Connection reference '$($r.LogicalName)' still has a placeholder ConnectionId."
        $errors++
    }
    $actualRefs.Remove($r.LogicalName)
}
foreach ($name in $actualRefs.Keys) {
    Write-Finding warning "Connection reference '$name' is not part of the solution and will be ignored."
}

$actualVars = @{}
foreach ($v in @($settings.EnvironmentVariables) | Where-Object { $_ }) { $actualVars[$v.SchemaName] = $v }
foreach ($v in @($expected.EnvironmentVariables) | Where-Object { $_ }) {
    if (-not $actualVars.ContainsKey($v.SchemaName) -or [string]::IsNullOrEmpty([string] $actualVars[$v.SchemaName].Value)) {
        Write-Finding warning "Environment variable '$($v.SchemaName)' has no value; the solution default will be used."
    }
    $actualVars.Remove($v.SchemaName)
}
foreach ($name in $actualVars.Keys) {
    Write-Finding warning "Environment variable '$name' is not part of the solution and will be ignored."
}

if ($errors -gt 0) {
    throw "$errors problem(s) found in '$SettingsFile'."
}
Write-Host "Deployment settings '$SettingsFile' look complete."
