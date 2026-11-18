<#
.SYNOPSIS
    Creates or refreshes per-environment deployment settings files for a solution.

.DESCRIPTION
    Runs `pac solution create-settings` against an unpacked solution folder (or a
    solution zip) to discover its environment variables and connection
    references, then merges the result into one settings file per target
    environment.

    Values already present in an existing file are kept, so the script is safe
    to re-run after every export. New components are added with placeholder
    values and a warning, and components that no longer exist in the solution
    are removed.

    Only the properties the import actually reads are written (SchemaName/Value
    and LogicalName/ConnectionId/ConnectorId). The display names, descriptions
    and default values that pac emits change whenever a maker edits a label and
    would otherwise show up as noise in every pull request.

.PARAMETER SolutionFolder
    Path to the unpacked solution root (the folder that contains Other/).

.PARAMETER SolutionZip
    Path to a packed solution zip. Use instead of -SolutionFolder.

.PARAMETER OutputFolder
    Folder that holds <environment>.json files. Defaults to ./deployment-settings.

.PARAMETER Environment
    Target environment names. One file is written per name.

.EXAMPLE
    ./scripts/New-DeploymentSettings.ps1 -SolutionFolder solutions/CoreCustomizations/src

.EXAMPLE
    ./scripts/New-DeploymentSettings.ps1 -SolutionFolder solutions/Sales/src `
        -OutputFolder deployment-settings/Sales -Environment test, uat, prod

.NOTES
    Requires the Power Platform CLI (pac) on PATH. No authentication is needed;
    create-settings works offline.
#>
#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Folder')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Folder')]
    [string] $SolutionFolder,

    [Parameter(Mandatory, ParameterSetName = 'Zip')]
    [string] $SolutionZip,

    [string] $OutputFolder = (Join-Path $PSScriptRoot '..' 'deployment-settings'),

    [string[]] $Environment = @('test', 'prod')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$placeholderConnectionId = '00000000-0000-0000-0000-000000000000'

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw 'pac was not found on PATH. Install the Power Platform CLI first.'
}

$generated = Join-Path ([System.IO.Path]::GetTempPath()) "settings-$([guid]::NewGuid()).json"
try {
    $source = if ($PSCmdlet.ParameterSetName -eq 'Zip') { @('--solution-zip', $SolutionZip) } else { @('--solution-folder', $SolutionFolder) }
    $pacOutput = & pac solution create-settings @source --settings-file $generated 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "pac solution create-settings failed:`n$($pacOutput -join "`n")"
    }
    $discovered = Get-Content $generated -Raw | ConvertFrom-Json
}
finally {
    Remove-Item $generated -ErrorAction SilentlyContinue
}

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

foreach ($envName in $Environment) {
    $path = Join-Path $OutputFolder "$envName.json"
    $existing = if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json } else { $null }

    $existingVars = @{}
    $existingRefs = @{}
    if ($existing) {
        foreach ($v in @($existing.EnvironmentVariables)) { if ($v) { $existingVars[$v.SchemaName] = $v } }
        foreach ($r in @($existing.ConnectionReferences)) { if ($r) { $existingRefs[$r.LogicalName] = $r } }
    }

    $variables = foreach ($v in @($discovered.EnvironmentVariables) | Where-Object { $_ } | Sort-Object SchemaName) {
        if ($existingVars.ContainsKey($v.SchemaName)) {
            $value = $existingVars[$v.SchemaName].Value
            $existingVars.Remove($v.SchemaName)
        }
        else {
            Write-Warning "[$envName] New environment variable '$($v.SchemaName)'. Set its value in $path."
            $value = ''
        }
        [ordered]@{ SchemaName = $v.SchemaName; Value = $value }
    }

    $references = foreach ($r in @($discovered.ConnectionReferences) | Where-Object { $_ } | Sort-Object LogicalName) {
        if ($existingRefs.ContainsKey($r.LogicalName)) {
            $connectionId = $existingRefs[$r.LogicalName].ConnectionId
            $existingRefs.Remove($r.LogicalName)
        }
        else {
            Write-Warning "[$envName] New connection reference '$($r.LogicalName)'. Set its ConnectionId in $path."
            $connectionId = $placeholderConnectionId
        }
        [ordered]@{ LogicalName = $r.LogicalName; ConnectionId = $connectionId; ConnectorId = $r.ConnectorId }
    }

    foreach ($stale in $existingVars.Keys) { Write-Warning "[$envName] Removing environment variable '$stale'; it is no longer in the solution." }
    foreach ($stale in $existingRefs.Keys) { Write-Warning "[$envName] Removing connection reference '$stale'; it is no longer in the solution." }

    $settings = [ordered]@{
        EnvironmentVariables = @($variables)
        ConnectionReferences = @($references)
    }

    if ($PSCmdlet.ShouldProcess($path, 'Write deployment settings')) {
        $json = $settings | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
        Write-Verbose "Wrote $path"
    }
}
