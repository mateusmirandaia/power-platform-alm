<#
.SYNOPSIS
    Sets or bumps the version of an unpacked Dataverse solution.

.DESCRIPTION
    Updates the <Version> element in Other/Solution.xml of an unpacked solution
    folder and writes the resulting version to the pipeline.

    Dataverse versions have four parts (major.minor.build.revision). Use
    -Version to set an explicit value (for example from a release tag),
    -Bump to increment one part and reset the ones after it, or -Revision to
    only stamp the last part (typically the CI run number) while leaving the
    version that was committed in source untouched.

    `pac solution version` exists, but it can only change build and revision,
    so it cannot be used for release tags that move major or minor.

.PARAMETER SolutionFolder
    Path to the unpacked solution root (the folder that contains Other/).

.PARAMETER Version
    Explicit version. Three-part values (1.4.0) get a revision of 0.

.PARAMETER Bump
    Part to increment: Major, Minor, Build or Revision.

.PARAMETER Revision
    Value for the revision part only.

.OUTPUTS
    System.String. The new version. When running in GitHub Actions the value is
    also written to $GITHUB_OUTPUT as `version`.

.EXAMPLE
    ./scripts/Set-SolutionVersion.ps1 -SolutionFolder solutions/CoreCustomizations/src -Bump Minor

.EXAMPLE
    ./scripts/Set-SolutionVersion.ps1 -SolutionFolder solutions/CoreCustomizations/src -Version 1.4.0

.EXAMPLE
    ./scripts/Set-SolutionVersion.ps1 -SolutionFolder solutions/CoreCustomizations/src -Revision $env:GITHUB_RUN_NUMBER
#>
#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Bump')]
param(
    [Parameter(Mandatory)]
    [string] $SolutionFolder,

    [Parameter(Mandatory, ParameterSetName = 'Explicit')]
    [ValidatePattern('^\d+\.\d+\.\d+(\.\d+)?$')]
    [string] $Version,

    [Parameter(Mandatory, ParameterSetName = 'Bump')]
    [ValidateSet('Major', 'Minor', 'Build', 'Revision')]
    [string] $Bump,

    [Parameter(Mandatory, ParameterSetName = 'Revision')]
    [ValidateRange(0, 2147483647)]
    [int] $Revision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$solutionXml = Join-Path $SolutionFolder 'Other' 'Solution.xml'
if (-not (Test-Path $solutionXml -PathType Leaf)) {
    throw "Solution.xml not found at '$solutionXml'. Point -SolutionFolder at the unpacked solution root."
}

# Edit the file as text instead of round-tripping through XmlDocument. A DOM save
# rewrites whitespace, attribute quoting and the BOM, which turns a one-line
# version change into a noisy diff on every build.
$bytes = [System.IO.File]::ReadAllBytes($solutionXml)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$content = [System.IO.File]::ReadAllText($solutionXml)

$pattern = '(?<=<SolutionManifest>[\s\S]*?)<Version>(?<v>[^<]+)</Version>'
$found = [regex]::Matches($content, $pattern)
if ($found.Count -ne 1) {
    throw "Expected exactly one <Version> under <SolutionManifest> in '$solutionXml', found $($found.Count)."
}

$current = [version] $found[0].Groups['v'].Value
$parts = @($current.Major, $current.Minor, [math]::Max($current.Build, 0), [math]::Max($current.Revision, 0))

switch ($PSCmdlet.ParameterSetName) {
    'Explicit' {
        $parts = @($Version.Split('.') | ForEach-Object { [int] $_ })
        if ($parts.Count -eq 3) { $parts += 0 }
    }
    'Bump' {
        $index = [array]::IndexOf(@('Major', 'Minor', 'Build', 'Revision'), $Bump)
        $parts[$index]++
        for ($i = $index + 1; $i -lt 4; $i++) { $parts[$i] = 0 }
    }
    'Revision' {
        $parts[3] = $Revision
    }
}

$newVersion = $parts -join '.'

if ($newVersion -eq $current.ToString()) {
    Write-Verbose "Version already $newVersion; nothing to change."
}
elseif ($PSCmdlet.ShouldProcess($solutionXml, "Set version $current -> $newVersion")) {
    $updated = [regex]::Replace($content, $pattern, "<Version>$newVersion</Version>")
    [System.IO.File]::WriteAllText($solutionXml, $updated, [System.Text.UTF8Encoding]::new($hasBom))
    Write-Verbose "Updated $solutionXml from $current to $newVersion."
}

if ($env:GITHUB_OUTPUT) {
    "version=$newVersion" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

$newVersion
