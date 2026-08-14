<#
.SYNOPSIS
Compute the canonical desired state from catalogue snapshots.

.DESCRIPTION
Takes the snapshots of a Run and computes the desired state as the union of
all validated catalogue entries: services are de-duplicated by service Id and
blockable addresses by address Value. A snapshot that failed validation
contributes no entries but is still carried as a contribution so a report can
show why. Each snapshot is its own catalogue contribution record.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses
and Contributions collections.
#>
function Get-DesiredState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$Snapshot
    )

    $services = @{}
    $blockableAddresses = @{}
    $contributions = @()

    foreach ($snapshot in @($Snapshot)) {
        if ($snapshot.Validation.Status -eq 'Success') {
            foreach ($service in @($snapshot.Services)) {
                if (-not $services.ContainsKey($service.Id)) {
                    $services[$service.Id] = $service
                }
            }

            foreach ($address in @($snapshot.BlockableAddresses)) {
                if (-not $blockableAddresses.ContainsKey($address.Value)) {
                    $blockableAddresses[$address.Value] = $address
                }
            }
        }

        $contributions += $snapshot
    }

    [pscustomobject]@{
        Services           = @($services.Values)
        BlockableAddresses = @($blockableAddresses.Values)
        Contributions      = @($contributions)
    }
}