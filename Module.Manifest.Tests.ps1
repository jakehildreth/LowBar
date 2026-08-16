#requires -Version 5.1
# Reusable manifest tests for any PowerShell module.
# Usage via New-PesterContainer:
#   $container = New-PesterContainer -Path './Module.Manifest.Tests.ps1' `
#       -Data @{ ModuleRoot = 'C:\path\to\MyModule' }
#   Invoke-Pester -Container $container

param(
    # Absolute path to the module root directory (where the .psd1 lives).
    [Parameter(Mandatory)]
    [string]$ModuleRoot
)

BeforeDiscovery {
    $manifestFile = Get-ChildItem -Path $ModuleRoot -Filter '*.psd1' -File |
        Select-Object -First 1

    if (-not $manifestFile) {
        throw "No .psd1 manifest found in '$ModuleRoot'."
    }

    $script:ManifestPath = $manifestFile.FullName
    $script:ModuleName   = $manifestFile.BaseName
}

Describe 'Module Manifest - <ModuleName>' -Tag 'Unit', 'Manifest' {
    BeforeAll {
        $ManifestPath = $script:ManifestPath
        $ModuleName   = $script:ModuleName
    }

    Context 'Manifest file integrity' {
        It 'manifest file should exist' {
            $ManifestPath | Should -Exist
        }

        It 'Test-ModuleManifest should pass without errors' {
            { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It 'manifest should have a non-empty ModuleVersion' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Version | Should -Not -BeNullOrEmpty
        }

        It 'manifest should have a non-empty Author' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Author | Should -Not -BeNullOrEmpty
        }

        It 'manifest should have a non-empty Description' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Description | Should -Not -BeNullOrEmpty
        }

        It 'manifest should have a GUID' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Guid | Should -Not -BeNullOrEmpty
        }
    }

    Context 'PowerShell compatibility' {
        It 'should target PowerShell 5.1 or lower as minimum version' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            [version]$manifest.PowerShellVersion | Should -BeLessOrEqual ([version]'5.1')
        }

        It 'should declare Desktop edition compatibility' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        }

        It 'should declare Core edition compatibility' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.CompatiblePSEditions | Should -Contain 'Core'
        }
    }

    Context 'Module import' {
        It 'should import without errors' {
            { Import-Module $ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'should be loadable a second time without errors (idempotent import)' {
            { Import-Module $ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        AfterAll {
            Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'FunctionsToExport' {
        It 'FunctionsToExport should not be a wildcard' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.ExportedFunctions.Keys | Should -Not -Contain '*'
        }

        It 'FunctionsToExport should not be empty' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.ExportedFunctions.Count | Should -BeGreaterThan 0
        }

        It 'every function in FunctionsToExport should use an approved verb' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $approvedVerbs = (Get-Verb).Verb
            $unapproved = $manifest.ExportedFunctions.Keys | Where-Object {
                $verb = ($_ -split '-')[0]
                $approvedVerbs -notcontains $verb
            }
            $unapproved | Should -BeNullOrEmpty -Because "all exported functions must use approved PowerShell verbs"
        }
    }
}
