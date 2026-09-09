<#
.SYNOPSIS
Classify a catalogue's unrepresentable values that are covered by its
representable wildcard domain entries.

.DESCRIPTION
A covered address is an address the desired state would enforce
anyway through a broader already-enforced entry, so the catalogue does not
need it. This pure, generic helper partitions Candidates into the covered
subset: a candidate is covered when its normalized tail equals the root of an
existing wildcard domain entry or ends with that root at a label boundary
('*.example.com' covers every host under 'example.com', so 'foo.example.com'
and 'example.com' are covered but 'badexample.com' is not). A candidate
covered only by a narrower sibling entry (e.g. 'cloud.example.com' present,
'*.example.com' absent) is not covered. Each candidate and each representable
address is normalized first by stripping any http(s) scheme, port, and
path/query, leaving the address tail. Covering is decided only against the
caller's own representable addresses, so it never crosses catalogue sources.

.OUTPUTS
The Candidates whose Value is covered, one object each.
#>
function Get-CoveredBlockableAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$RepresentableAddresses,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidates
    )

    $wildcardRoots = @(
        foreach ($address in @($RepresentableAddresses)) {
            $value = [string]$address.Value
            if ($value.StartsWith('*.')) {
                Get-NormalizedAddressTail -Value $value.Substring(2)
            }
        }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $covered = @(
        foreach ($candidate in @($Candidates)) {
            $tail = Get-NormalizedAddressTail -Value ([string]$candidate.Value)
            $isCovered = $false
            foreach ($root in $wildcardRoots) {
                if ($tail -ieq $root -or $tail.EndsWith(".$root", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isCovered = $true
                    break
                }
            }
            if ($isCovered) { $candidate }
        }
    )

    @($covered)
}

<#
.SYNOPSIS
Normalize an address value down to its address tail.

.DESCRIPTION
Strips an http(s) scheme, any port, and any path/query/fragment so that
'https://host.example.com:8443/path?q=1' and 'host.example.com' both reduce
to the same tail 'host.example.com'.

.OUTPUTS
System.String, the normalized address tail.
#>
function Get-NormalizedAddressTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $tail = $Value.Trim()
    $tail = $tail -replace '^https?://', ''

    $cutIndex = $tail.IndexOfAny([char[]]('/#?'))
    if ($cutIndex -ge 0) {
        $tail = $tail.Substring(0, $cutIndex)
    }

    $tail -replace ':\d+$', ''
}
