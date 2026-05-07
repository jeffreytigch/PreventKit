
# Get CSV
$CSV = (Invoke-WebRequest "https://lolrmm.io/api/rmm_domains.csv").Content | ConvertFrom-CSV

# Step 1: Transform wildcard domains to TABL-compatible patterns
# Rules:
#   *.domain.com  -> ~domain.com  (wildcard subdomain with dot)
#   *domain.com   -> ~domain.com  (wildcard subdomain without dot - strip *, add ~)
#   prefix*.x.com -> skip         (mid-string wildcard, no TABL equivalent)
#   After transform: skip any entry whose domain starts with '-' (invalid label)


$transformedRows = @(foreach ($Entry in $CSV) {
    $uri = $Entry.URI
    if ($uri -match '^\*\.(.+)$') {
        # *.domain.com -> ~domain.com
        $transformed = '~' + $Matches[1]
    } elseif ($uri -match '^\*([^*].*)$') {
        # *domain.com -> ~domain.com (strip leading *, add ~)
        $transformed = '~' + $Matches[1]
    } elseif ($uri -match '\*') {
        # mid-string or unsupported wildcard — skip
        continue
    } else {
        $transformed = $uri
    }

    # Skip entries where the domain label starts with '-' (e.g. ~-dms.zoho.com.cn)
    if ($transformed -match '^~?-') { continue }

    [pscustomobject]@{
        URI      = $transformed
        RMM_Tool = $Entry.RMM_Tool
    }
})

# Step 2: Deduplicate - keep the ~ version if both exist
$uniqueDomains = @{}

foreach ($row in $transformedRows) {
    $domain = $row.URI
    $baseDomain = $domain -replace '^~', ''
    # Add if new, or replace if the new one has ~ and the old one doesn't
    if (-not $uniqueDomains[$baseDomain] -or ($domain -match '^~' -and $uniqueDomains[$baseDomain].URI -notmatch '^~')) {
        $uniqueDomains[$baseDomain] = $row
    }
}

$deduplicatedRows = @($uniqueDomains.Values)
$deduplicatedDomains = @($deduplicatedRows | Select-Object -ExpandProperty URI)

# Step 6: Connect to Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Green
Connect-ExchangeOnline -SkipLoadingCmdletHelp

# Step 7: Get current TABL entries for URLs
Write-Host "Fetching current Tenant Allow/Block List..." -ForegroundColor Green
$currentTABL = @(Get-TenantAllowBlockListItems -ListType URL -Block -ErrorAction SilentlyContinue)
$currentEntries = @($currentTABL | Select-Object -ExpandProperty Value)

Write-Host "Current TABL has $($currentEntries.Count) URL block entries" -ForegroundColor Cyan

# Step 8: Calculate diff between current list and updated list
Write-Host "Calculating differences..." -ForegroundColor Green
$entriesToAdd = @($deduplicatedDomains | Where-Object { $_ -notin $currentEntries })

Write-Host "Entries to add: $($entriesToAdd.Count)" -ForegroundColor Yellow

# Step 9: Update all domains in TABL
if ($entriesToAdd.Count -gt 0) {
    Write-Host "Adding $($entriesToAdd.Count) new entries to TABL..." -ForegroundColor Green
    $entriesToAdd | ForEach-Object -Begin { $batch = @() } -Process {
        $batch += $_
        if ($batch.Count -eq 20 -or $_ -eq $entriesToAdd[-1]) {
            try {
                New-TenantAllowBlockListItems -ListType URL -Block -Entries $batch -NoExpiration -Notes "<PreventKit> - Automatically added" -ErrorAction Stop
                Write-Host "Added $($batch.Count) entries" -ForegroundColor Cyan
            } catch {
                Write-Host "Error adding entries: $_" -ForegroundColor Red
            }
            $batch = @()
        }
    }
}

Write-Host "Update complete!" -ForegroundColor Green