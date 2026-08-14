<#
.SYNOPSIS
Compute the canonical desired state from catalogue snapshots.

.DESCRIPTION
Takes the snapshots of a Run and computes the desired state as the union of
all validated catalogue entries: services are de-duplicated by service Id and
blockable addresses by address Value. A snapshot that failed validation
contributes no entries but is still carried as a contribution so a report can
show why. Each snapshot is its own catalogue contribution record.

Invocation exceptions are non-overriding: an entry that matches an exception
key drops out of the desired state entirely (services by 'service:<Id>' keys,
blockable addresses by 'domain:<Value>' keys or the service key of their
service) and is recorded in the Suppressed collection so a report can show what
was suppressed. No allow rule is ever created; suppression only removes.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses,
Contributions and Suppressed collections.
#>
function Get-DesiredState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Snapshot,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ExceptionKey = @()
    )

    $services = @{}
    $blockableAddresses = @{}
    $contributions = @()
    $suppressed = @()
    $suppressedSeen = @{}

    foreach ($snapshot in @($Snapshot)) {
        if ($snapshot.Validation.Status -eq 'Success') {
            foreach ($service in @($snapshot.Services)) {
                if (Test-InvocationException -ExceptionKey $ExceptionKey -ServiceId ([string]$service.Id)) {
                    $key = "Service:$($service.Id)"
                    if (-not $suppressedSeen.ContainsKey($key)) {
                        $suppressedSeen[$key] = $true
                        $suppressed += [pscustomobject]@{ Kind = 'Service'; Entry = $service }
                    }
                    continue
                }

                if (-not $services.ContainsKey($service.Id)) {
                    $services[$service.Id] = $service
                }
            }

            foreach ($address in @($snapshot.BlockableAddresses)) {
                if (Test-InvocationException -ExceptionKey $ExceptionKey `
                        -ServiceId ([string]$address.ServiceId) -AddressValue ([string]$address.Value)) {
                    $key = "BlockableAddress:$($address.Value)"
                    if (-not $suppressedSeen.ContainsKey($key)) {
                        $suppressedSeen[$key] = $true
                        $suppressed += [pscustomobject]@{ Kind = 'BlockableAddress'; Entry = $address }
                    }
                    continue
                }

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
        Suppressed         = @($suppressed)
    }
}