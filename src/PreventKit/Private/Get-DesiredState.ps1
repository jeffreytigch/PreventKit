<#
.SYNOPSIS
Compute the canonical desired state from catalogue snapshots.

.DESCRIPTION
Takes the snapshots of a Run and computes the desired state as the union of
all validated catalogue entries: services are de-duplicated by service Id and
blockable addresses by address Value. A snapshot that failed validation
contributes no entries but is still carried as a contribution so a report can
show why. Each snapshot is its own catalogue contribution record.

Non-overriding exceptions drop matching entries out of the desired state
entirely (services by 'service:<Id>' keys, blockable addresses by
'domain:<Value>' keys or the service key of their service) and record them in
the Suppressed collection so a report can show what was suppressed. Invocation
exceptions are supplied per Run through ExceptionKey; global exceptions are
stored declarations supplied through GlobalExceptionKey and applied to every
Run. Each suppressed entry carries the Source it was suppressed by
('Invocation' or 'Global'). No allow rule is ever created; suppression only
removes.

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
        [string[]]$ExceptionKey = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$GlobalExceptionKey = @()
    )

    $services = @{}
    $blockableAddresses = @{}
    $contributions = @()
    $suppressed = @()
    $suppressedSeen = @{}

    foreach ($snapshot in @($Snapshot)) {
        if ($snapshot.Validation.Status -eq 'Success') {
            foreach ($service in @($snapshot.Services)) {
                $suppressedType = $null
                if (Test-ExceptionKey -ExceptionKey $ExceptionKey -ServiceId ([string]$service.Id)) {
                    $suppressedType = 'Invocation'
                }
                elseif (Test-ExceptionKey -ExceptionKey $GlobalExceptionKey -ServiceId ([string]$service.Id)) {
                    $suppressedType = 'Global'
                }

                if ($null -ne $suppressedType) {
                    $key = "Service:$($service.Id)"
                    if (-not $suppressedSeen.ContainsKey($key)) {
                        $suppressedSeen[$key] = $true
                        $suppressed += [pscustomobject]@{ Kind = 'Service'; Entry = $service; ExceptionType = $suppressedType }
                    }
                    continue
                }

                if (-not $services.ContainsKey($service.Id)) {
                    $services[$service.Id] = $service
                }
            }

            foreach ($address in @($snapshot.BlockableAddresses)) {
                $suppressedType = $null
                if (Test-ExceptionKey -ExceptionKey $ExceptionKey `
                        -ServiceId ([string]$address.ServiceId) -AddressValue ([string]$address.Value)) {
                    $suppressedType = 'Invocation'
                }
                elseif (Test-ExceptionKey -ExceptionKey $GlobalExceptionKey `
                        -ServiceId ([string]$address.ServiceId) -AddressValue ([string]$address.Value)) {
                    $suppressedType = 'Global'
                }

                if ($null -ne $suppressedType) {
                    $key = "BlockableAddress:$($address.Value)"
                    if (-not $suppressedSeen.ContainsKey($key)) {
                        $suppressedSeen[$key] = $true
                        $suppressed += [pscustomobject]@{ Kind = 'BlockableAddress'; Entry = $address; ExceptionType = $suppressedType }
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