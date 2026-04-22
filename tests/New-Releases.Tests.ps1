#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = Resolve-Path "$PSScriptRoot/../src/New-Releases.ps1"

    # Builds a minimal release object matching the gh JSON schema
    function New-Release {
        param([string]$TagName, [bool]$IsLatest = $false, [bool]$IsPrerelease = $false)
        [PSCustomObject]@{
            name         = $TagName
            tagName      = $TagName
            isLatest     = $IsLatest
            isPrerelease = $IsPrerelease
            isDraft      = $false
        }
    }

    # Serializes release objects to a JSON string for use in gh mock responses
    function ConvertTo-ReleasesJson {
        param([PSCustomObject[]]$Releases)
        if (!$Releases) { return '[]' }
        $Releases | ConvertTo-Json -Compress -AsArray
    }
}

Describe 'New-Releases.ps1' {

    BeforeEach {
        Mock git { }
        Mock gh {
            if ($args[0] -eq 'release' -and $args[1] -eq 'list') { return '[]' }
            if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Version bumping - no existing releases' {

        It 'creates first release at v0.1.0 when no releases exist' {
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v0.1.0'
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Version bumping - existing releases' {

        It 'bumps patch: v1.2.3 → v1.2.4' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.2.4'
            }
        }

        It 'bumps minor: v1.2.3 → v1.3.0' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType minor
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.3.0'
            }
        }

        It 'bumps major: v1.2.3 → v2.0.0' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType major
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v2.0.0'
            }
        }

        It 'respects the highest version even when releases are unordered' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.9.0'
                        New-Release 'v1.10.0' -IsLatest $true
                        New-Release 'v1.8.5'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.10.1'
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Stable tag filtering' {

        It 'ignores pre-release/labeled tags when resolving latest version' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3'
                        New-Release 'v1.3.0-beta' -IsLatest $true -IsPrerelease $true
                        New-Release 'v1.3.0-rc'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.2.4'
            }
        }

        It 'ignores floating minor/major tags' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3'
                        New-Release 'v1.2'
                        New-Release 'v1' -IsLatest $true
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.2.4'
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Full semver release - release args' {

        It 'passes --latest when no label or pre-release' {
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args -contains '--latest'
            }
        }

        It 'passes --latest=false and --prerelease=true when PreRelease is set' {
            & $script:ScriptPath -UpdateType patch -PreRelease $true
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and
                $args -contains '--latest=false' -and $args -contains '--prerelease=true'
            }
        }

        It 'passes --latest=false and --prerelease=false when Label is set' {
            & $script:ScriptPath -UpdateType patch -Label 'alpha'
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and
                $args -contains '--latest=false' -and $args -contains '--prerelease=false'
            }
        }

        It 'includes --notes-start-tag pointing to the previous stable patch' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.2.4' -and
                $args -contains '--notes-start-tag' -and $args -contains 'v1.2.3'
            }
        }

        It 'does not include --notes-start-tag when no previous release exists' {
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and
                $args -notcontains '--notes-start-tag'
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Label handling' {

        It 'appends label to the semver tag' {
            & $script:ScriptPath -UpdateType patch -Label 'alpha'
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v0.1.0-alpha'
            }
        }

        It 'strips a leading dash from the label' {
            & $script:ScriptPath -UpdateType patch -Label '-rc'
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v0.1.0-rc'
            }
        }

        It 'skips minor and major release creation when a label is present' {
            & $script:ScriptPath -UpdateType patch -Label 'alpha'
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and
                ($args[1] -eq 'create' -or $args[1] -eq 'edit') -and
                ($args[2] -eq 'v0.1' -or $args[2] -eq 'v0')
            } -Times 0
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Pre-release handling' {

        It 'skips minor and major release creation when PreRelease is set' {
            & $script:ScriptPath -UpdateType patch -PreRelease $true
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and
                ($args[1] -eq 'create' -or $args[1] -eq 'edit') -and
                ($args[2] -eq 'v0.1' -or $args[2] -eq 'v0')
            } -Times 0
        }
    }

    # ---------------------------------------------------------------------------
    Context 'git tagging' {

        It 'force-creates the full semver tag' {
            & $script:ScriptPath -UpdateType patch
            Should -Invoke git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-fa' -and $args[2] -eq 'v0.1.0'
            }
        }

        It 'force-creates the minor floating tag' {
            & $script:ScriptPath -UpdateType patch
            Should -Invoke git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-fa' -and $args[2] -eq 'v0.1'
            }
        }

        It 'force-creates the major floating tag' {
            & $script:ScriptPath -UpdateType patch
            Should -Invoke git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-fa' -and $args[2] -eq 'v0'
            }
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Minor release management' {

        It 'creates a new minor release on minor bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType minor
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.3'
            }
        }

        It 'edits existing minor release on patch bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    # v1.1.5 is in releases so $startTagMinor resolves to it and the edit path is taken
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v1.1.5'
                        New-Release 'v1.2'
                        New-Release 'v1'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'edit' -and $args[2] -eq 'v1.2' -and
                $args -contains '--notes-start-tag' -and $args -contains 'v1.1.5'
            }
        }

        It 'deletes old minor release before recreating on minor bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v1.3'   # old minor release already exists
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType minor
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'delete' -and $args[2] -eq 'v1.3'
            }
        }

        It 'uses the latest patch of the previous minor as notes-start-tag' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    # Latest stable is v1.1.5; minor bump produces v1.2.0; previousMinor=1 → v1.1.5 is the start tag
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.1.5' -IsLatest $true
                        New-Release 'v1.1.3'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType minor
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v1.2' -and
                $args -contains '--notes-start-tag' -and $args -contains 'v1.1.5'
            }
        }

        It 'falls back to latestSemver as notes-start-tag for minor release on major bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType major
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v2.0' -and
                $args -contains '--notes-start-tag' -and $args -contains 'v1.2.3'
            }
        }

        It 'emits a warning when the minor start tag has no release during a patch edit' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    # v1.2 exists as a release, but there are no v1.1.* tags and no v1.1 release
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v1.2'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            $warnings = & $script:ScriptPath -UpdateType patch 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Where-Object { $_ -match 'Skipping notes update for v1\.2' } | Should -Not -BeNullOrEmpty
        }
    }

    # ---------------------------------------------------------------------------
    Context 'Major release management' {

        It 'creates a new major release on major bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(New-Release 'v1.2.3' -IsLatest $true)
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType major
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v2'
            }
        }

        It 'edits existing major release on patch bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    # v0.9.0 is in releases so $startTagMajor resolves to it and the edit path is taken
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v1.1.5'
                        New-Release 'v1.2'
                        New-Release 'v0.9.0'
                        New-Release 'v1'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType patch
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'edit' -and $args[2] -eq 'v1' -and
                $args -contains '--notes-start-tag' -and $args -contains 'v0.9.0'
            }
        }

        It 'deletes old major release before recreating on major bump' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v2'  # old major release already exists
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType major
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'delete' -and $args[2] -eq 'v2'
            }
        }

        It 'uses the latest patch of the previous major as notes-start-tag' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    # Two v1.x.x patches present; the script must pick the highest (v1.2.3, not v1.0.5)
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v1.0.5'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            & $script:ScriptPath -UpdateType major
            Should -Invoke gh -ParameterFilter {
                $args[0] -eq 'release' -and $args[1] -eq 'create' -and $args[2] -eq 'v2' -and
                $args -contains '--notes-start-tag' -and $args -contains 'v1.2.3'
            }
        }

        It 'emits a warning when the major start tag has no release during a patch edit' {
            Mock gh {
                if ($args[0] -eq 'release' -and $args[1] -eq 'list') {
                    # v1 exists as a release, but there are no v0.* tags and no v0 release
                    return ConvertTo-ReleasesJson @(
                        New-Release 'v1.2.3' -IsLatest $true
                        New-Release 'v1.2'
                        New-Release 'v1'
                    )
                }
                if ($args[0] -eq 'repo') { return 'https://github.com/test/repo' }
            }
            $warnings = & $script:ScriptPath -UpdateType patch 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Where-Object { $_ -match 'Skipping notes update for v1:' } | Should -Not -BeNullOrEmpty
        }
    }
}
