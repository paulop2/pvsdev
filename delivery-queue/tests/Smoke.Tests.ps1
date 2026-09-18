Set-StrictMode -Version Latest

Describe 'ambiente' {
    It 'carrega Pester 6' {
        (Get-Module -ListAvailable Pester |
            Sort-Object Version -Descending |
            Select-Object -First 1).Version.Major | Should -Be 6
    }

    It 'roda no Windows PowerShell 5.1' {
        $PSVersionTable.PSVersion.Major | Should -Be 5
        $PSVersionTable.PSVersion.Minor | Should -Be 1
    }
}
