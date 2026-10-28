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

Describe 'Module Manifest - <ModuleName>' -Tag 'Unit', 'Manifest' -ForEach @(@{ SourcePath = $script:ManifestPath }) {
    BeforeAll {
        $ManifestPath = $SourcePath
        $ModuleName   = [System.IO.Path]::GetFileNameWithoutExtension($ManifestPath)
    }

    Context 'Manifest file integrity' {
        It 'manifest file should exist' {
            $ManifestPath | Should -Exist -Because 'Recommendation: Create a .psd1 module manifest at the expected module root path.'
        }

        It 'Test-ModuleManifest should pass without errors' {
            { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw -Because 'Recommendation: Correct the manifest fields and file references identified by Test-ModuleManifest.'
        }

        It 'manifest should have a non-empty ModuleVersion' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Version | Should -Not -BeNullOrEmpty -Because 'Recommendation: Set ModuleVersion to a valid version in the module manifest.'
        }

        It 'manifest should have a non-empty Author' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Author | Should -Not -BeNullOrEmpty -Because 'Recommendation: Set Author to a non-empty author name in the module manifest.'
        }

        It 'manifest should have a non-empty Description' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Description | Should -Not -BeNullOrEmpty -Because 'Recommendation: Set Description to a non-empty summary in the module manifest.'
        }

        It 'manifest should have a GUID' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.Guid | Should -Not -BeNullOrEmpty -Because 'Recommendation: Generate a GUID with New-Guid and set GUID in the module manifest.'
        }
    }

    Context 'PowerShell compatibility' {
        It 'should target PowerShell 5.1 or lower as minimum version' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            [version]$manifest.PowerShellVersion | Should -BeLessOrEqual ([version]'5.1') -Because "Recommendation: Make the module compatible with PowerShell 5.1 and set PowerShellVersion to '5.1' or lower in the manifest."
        }

        It 'should declare Desktop edition compatibility' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.CompatiblePSEditions | Should -Contain 'Desktop' -Because "Recommendation: Verify Windows PowerShell compatibility and add 'Desktop' to CompatiblePSEditions."
        }

        It 'should declare Core edition compatibility' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.CompatiblePSEditions | Should -Contain 'Core' -Because "Recommendation: Verify PowerShell Core compatibility and add 'Core' to CompatiblePSEditions."
        }
    }

    Context 'Module import' {
        It 'should import without errors' {
            { Import-Module $ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw -Because 'Recommendation: Fix the import error shown below; check RootModule, required modules, and module initialization code.'
        }

        It 'should be loadable a second time without errors (idempotent import)' {
            { Import-Module $ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw -Because 'Recommendation: Make module initialization safe to repeat and fix the reported import error.'
        }

        AfterAll {
            Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'FunctionsToExport' {
        It 'FunctionsToExport should not be a wildcard' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.ExportedFunctions.Keys | Should -Not -Contain '*' -Because 'Recommendation: Replace wildcard function exports with an explicit list of public function names in FunctionsToExport.'
        }

        It 'FunctionsToExport should not be empty' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $manifest.ExportedFunctions.Count | Should -BeGreaterThan 0 -Because 'Recommendation: Add public function names to FunctionsToExport and ensure the root module exports them.'
        }

        It 'every function in FunctionsToExport should use an approved verb' {
            $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
            $approvedVerbs = (Get-Verb).Verb
            $unapproved = $manifest.ExportedFunctions.Keys | Where-Object {
                $verb = ($_ -split '-')[0]
                $approvedVerbs -notcontains $verb
            }
            $unapproved | Should -BeNullOrEmpty -Because 'all exported functions must use approved PowerShell verbs. Recommendation: Rename the affected functions using verbs from Get-Verb and update their exports and callers.'
        }
    }
}
