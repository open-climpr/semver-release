[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet("major", "minor", "patch")]
    [string]
    $UpdateType,

    [Parameter(Mandatory = $false)]
    [string]
    $Label,

    [Parameter(Mandatory = $false)]
    [bool]
    $PreRelease = $false
)

#* Defaults
$releases = gh release list --limit 500 --json "name,tagName,isLatest,isPrerelease,isDraft" | ConvertFrom-Json -NoEnumerate

$stableSemverTags = $releases.tagName | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }

$latestSemver = $stableSemverTags | Sort-Object { ($_ -replace '^v') -as [version] } | Select-Object -Last 1

if ($latestSemver) {
    $parts = ($latestSemver -replace '^v') -split '\.'
    $newMajor = [int]$parts[0]
    $newMinor = [int]$parts[1]
    $newPatch = [int]$parts[2]
          
    switch ($UpdateType) {
        "major" {
            $newMajor++
            $newMinor = 0
            $newPatch = 0
        }
        "minor" {
            $newMinor++
            $newPatch = 0
        }
        "patch" { $newPatch++ }
    }
}
else {
    $newMajor = 0
    $newMinor = 1
    $newPatch = 0
}

#* Calculate semver tags
$newSemver = "v$newMajor.$newMinor.$newPatch"
$newSemverMinor = "v$newMajor.$newMinor"
$newSemverMajor = "v$newMajor"

#* Append label if applicable
if ($Label) { $newSemver = "$newSemver-$($Label.TrimStart('-'))" }

#* Create full semver release
Write-Host "Releasing $newSemver"
git tag -fa $newSemver -m "Automated release: $newSemver"
git push --tags --force

$releaseArgs = @('--generate-notes')
if (!($Label -or $PreRelease)) {
    $releaseArgs += '--latest'
}
else {
    $releaseArgs += '--latest=false'
    $releaseArgs += "--prerelease=$($PreRelease.ToString().ToLower())"
}
if ($latestSemver) { $releaseArgs += @('--notes-start-tag', $latestSemver) }

gh release create $newSemver @releaseArgs

#* Create/Update minor release tag. Only if label is not present and release is not tagged as pre-release
if (!($Label -or $PreRelease)) {
    $repoName = gh repo view --json url -q ".url"
    git tag -fa $newSemverMinor -m "Automated release: $newSemverMinor"
    git push --tags --force

    $existingMinor = $releases | Where-Object { $_.tagName -eq $newSemverMinor }
    $releaseMinor = !$existingMinor -or $UpdateType -eq "minor"

    $previousMinor = $newMinor -gt 0 ? $newMinor - 1 : 0
    $latestPrevMinorPatch = $stableSemverTags |
        Where-Object { $_ -match "^v$newMajor\.$previousMinor\." } |
        Sort-Object { ($_ -replace '^v') -as [version] } |
        Select-Object -Last 1
    $startTagMinor = $latestPrevMinorPatch
    if (!$startTagMinor -and $UpdateType -eq 'major') { $startTagMinor = $latestSemver }
    if (!$startTagMinor) { $startTagMinor = "v$newMajor.$previousMinor" }

    if ($releaseMinor) {
        Write-Host "Releasing $newSemverMinor"
        if ($existingMinor) {
            Write-Host "Deleting old release $newSemverMinor"
            gh release delete $newSemverMinor -y
        }
        if ($releases | Where-Object { $_.tagName -eq $startTagMinor }) {
            gh release create $newSemverMinor --latest=false --generate-notes --notes-start-tag $startTagMinor
        }
        else {
            gh release create $newSemverMinor --latest=false --notes "**Full Changelog**: $repoName/commits/$newSemverMinor"
        }
    }
    elseif ($existingMinor) {
        if ($releases | Where-Object { $_.tagName -eq $startTagMinor }) {
            gh release edit $newSemverMinor --generate-notes --notes-start-tag $startTagMinor
        }
        else {
            Write-Warning "Skipping notes update for ${newSemverMinor}: start tag '$startTagMinor' not found"
        }
    }

    #* Create/Update major release tag. Only if label is not present
    git tag -fa $newSemverMajor -m "Automated release: $newSemverMajor"
    git push --tags --force

    $existingMajor = $releases | Where-Object { $_.tagName -eq $newSemverMajor }
    $releaseMajor = !$existingMajor -or $UpdateType -eq "major"

    $previousMajor = $newMajor -gt 0 ? $newMajor - 1 : 0
    $latestPrevMajorPatch = $stableSemverTags |
        Where-Object { $_ -match "^v$previousMajor\." } |
        Sort-Object { ($_ -replace '^v') -as [version] } |
        Select-Object -Last 1
    $startTagMajor = $latestPrevMajorPatch ? $latestPrevMajorPatch : "v$previousMajor"

    if ($releaseMajor) {
        Write-Host "Releasing $newSemverMajor"
        if ($existingMajor) {
            Write-Host "Deleting old release $newSemverMajor"
            gh release delete $newSemverMajor -y
        }
        if ($releases | Where-Object { $_.tagName -eq $startTagMajor }) {
            gh release create $newSemverMajor --latest=false --generate-notes --notes-start-tag $startTagMajor
        }
        else {
            gh release create $newSemverMajor --latest=false --notes "**Full Changelog**: $repoName/commits/$newSemverMajor"
        }
    }
    elseif ($existingMajor) {
        if ($releases | Where-Object { $_.tagName -eq $startTagMajor }) {
            gh release edit $newSemverMajor --generate-notes --notes-start-tag $startTagMajor
        }
        else {
            Write-Warning "Skipping notes update for ${newSemverMajor}: start tag '$startTagMajor' not found"
        }
    }
}