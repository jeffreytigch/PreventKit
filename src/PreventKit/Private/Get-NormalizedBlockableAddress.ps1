<#
.SYNOPSIS
Recover a representable blockable address from a catalogue's raw address value.

.DESCRIPTION
Catalogue sources occasionally publish blocking patterns that are not directly
representable as a URL, domain, or IP address, even though their intent is
clear. This pure, adapter-agnostic helper applies a fixed set of recoveries to
any catalogue's raw address value and returns the recovered address, or the
original value when no safe recovery exists, so no source format knowledge is
required to use it.

Recoveries are attempted only when the raw value is not already representable,
so plain URLs, domains, and IP addresses are returned untouched.

The following recoveries never widen the pattern's scope and always apply:

- A trailing port, including the wildcard port form, is dropped
  ('host.example.com:*' -> 'host.example.com').
- A trailing pattern wildcard is dropped
  ('*.host.example.com*' -> '*.host.example.com').
- A leading pattern wildcard without a separating dot becomes a subdomain
  wildcard ('*host.example.com' -> '*.host.example.com').

The following recovery widens the pattern to a wildcard parent domain and only
applies when RecoverDerivedWildcards is set, because the derived entry can block
unrelated names that share the parent:

- A pattern wildcard inside a label is recovered as a wildcard subdomain of the
  labels that follow the last wildcard-bearing label
  ('agents*-cloud.example.com' -> '*.example.com').

Callers should surface recovered values for review.

.PARAMETER Value
The raw address value published by the catalogue source.

.PARAMETER RecoverDerivedWildcards
Also recover patterns that require deriving a broader wildcard parent domain.
Disabled by default because the derived entry can block unrelated names.

.OUTPUTS
System.String, the recovered address, or the original Value when it cannot be
safely recovered.
#>
function Get-NormalizedBlockableAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter()]
        [switch]$RecoverDerivedWildcards
    )

    $candidate = $Value.Trim()

    if (Get-BlockableAddressType -Value $candidate) {
        return $candidate
    }

    # Drop a trailing port, including the wildcard port form (':*').
    $candidate = $candidate -replace ':(\*|\d+)$', ''

    # Drop a trailing pattern wildcard.
    $candidate = $candidate -replace '\*+$', ''

    # A leading wildcard without a separating dot is a subdomain wildcard.
    if ($candidate -match '^\*(?!\.)') {
        $candidate = '*.' + $candidate.Substring(1)
    }

    if (Get-BlockableAddressType -Value $candidate) {
        return $candidate
    }

    if (-not $RecoverDerivedWildcards) {
        return $Value
    }

    # A wildcard inside a label: recover a wildcard subdomain from the labels
    # that follow the last wildcard-bearing label. This widens the pattern's
    # scope, so it is only attempted when the caller opts in.
    $labels = @($candidate.Split('.'))
    $lastWildcard = -1
    for ($index = 0; $index -lt $labels.Count; $index++) {
        if ($labels[$index].Contains('*')) {
            $lastWildcard = $index
        }
    }

    if ($lastWildcard -ge 0 -and ($lastWildcard + 1) -lt $labels.Count) {
        $tail = ($labels[($lastWildcard + 1)..($labels.Count - 1)] -join '.')
        if ($tail.Contains('.') -and (Get-BlockableAddressType -Value $tail)) {
            return '*.' + $tail
        }
    }

    return $Value
}
