# The Run engine reconciles both enforcement targets by default. This setup
# installs inert target seams so catalogue-focused tests never touch live state.
InModuleScope PreventKit {
    if (-not (Get-Command -Name Get-TenantAllowBlockListItems -ErrorAction SilentlyContinue)) {
        function Get-TenantAllowBlockListItems { [CmdletBinding()] param($ListType, [switch]$Block) }
    }
    Mock Get-ExchangeOnlineSession { return [pscustomobject]@{ IsConnected = $true } }
    Mock Get-TenantAllowBlockListItems { return @() }
    Mock Add-TablManagedEntry { return $Values }
    Mock Remove-TablManagedEntry { }
    Mock Get-CniTokenFromAzureCli { return 'test-token' }
    Mock Get-CniCurrentIndicators { return @() }
    Mock Add-CniManagedEntry { return $Mappings }
    Mock Remove-CniManagedEntry { }
}
