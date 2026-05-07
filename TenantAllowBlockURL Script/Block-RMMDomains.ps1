<#
.SYNOPSIS
    Blokkeert RMM-domeinen in Microsoft 365 Tenant Allow/Block List op basis van data van lolrmm.io

.DESCRIPTION
    Dit script haalt de lijst met RMM-domeinen op van https://lolrmm.io/api/rmm_domains.csv
    en voegt deze toe aan de Microsoft 365 Tenant Allow/Block List als geblokkeerde domeinen.
    Dit helpt om ongewenste Remote Monitoring & Management tools te blokkeren.

.PARAMETER NoExpiration
    Indien opgegeven, worden de block entries permanent toegevoegd (vervallen niet).
    Anders vervallen de entries na 90 dagen.

.PARAMETER ExpirationDays
    Aantal dagen voordat de block entries vervallen (max 90 dagen).
    Standaard: 90 dagen

.PARAMETER DryRun
    Test de werking zonder daadwerkelijk domeinen toe te voegen aan de block list.

.PARAMETER Notes
    Optionele notitie die wordt toegevoegd aan de block entries.

.EXAMPLE
    .\Block-RMMDomains.ps1 -NoExpiration
    Voegt alle RMM-domeinen permanent toe aan de block list

.EXAMPLE
    .\Block-RMMDomains.ps1 -ExpirationDays 30
    Voegt RMM-domeinen toe met vervaldatum van 30 dagen

.EXAMPLE
    .\Block-RMMDomains.ps1 -DryRun
    Test het script zonder wijzigingen door te voeren

.NOTES
    Versie: 1.0
    Auteur: GitHub Copilot
    Datum: 2026-05-07
    
    Vereisten:
    - Exchange Online PowerShell module
    - Microsoft 365 admin rechten (Security Administrator of Global Administrator)
    - Defender for Office 365 licentie (voor hogere limieten)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$NoExpiration,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 90)]
    [int]$ExpirationDays = 90,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [string]$Notes = "RMM domain blocked via lolrmm.io list"
)

# Configuratie
$csvUrl = "https://lolrmm.io/api/rmm_domains.csv"
$logFile = "RMM-Domains-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Functie voor logging
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Schrijf naar console met kleur
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Schrijf naar logfile
    Add-Content -Path $logFile -Value $logMessage
}

# Functie om Exchange Online PowerShell module te controleren en installeren
function Test-ExchangeOnlineModule {
    Write-Log "Controleren van Exchange Online PowerShell module..."
    
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Log "Exchange Online Management module niet gevonden. Installeren..." -Level Warning
        try {
            Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
            Write-Log "Exchange Online Management module succesvol geïnstalleerd." -Level Success
        }
        catch {
            Write-Log "Fout bij installeren van Exchange Online Management module: $_" -Level Error
            return $false
        }
    }
    else {
        Write-Log "Exchange Online Management module is al geïnstalleerd." -Level Success
    }
    
    return $true
}

# Functie om verbinding te maken met Exchange Online
function Connect-ExchangeOnlineService {
    Write-Log "Verbinding maken met Exchange Online..."
    
    try {
        # Controleer of er al een verbinding is
        $existingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
        
        if ($existingConnection) {
            Write-Log "Er is al een actieve Exchange Online verbinding." -Level Success
            return $true
        }
        
        # Maak nieuwe verbinding
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Log "Succesvol verbonden met Exchange Online." -Level Success
        return $true
    }
    catch {
        Write-Log "Fout bij verbinden met Exchange Online: $_" -Level Error
        return $false
    }
}

# Functie om RMM-domeinen op te halen
function Get-RMMDomains {
    Write-Log "Ophalen van RMM-domeinen van $csvUrl..."
    
    try {
        # Download CSV data
        $response = Invoke-WebRequest -Uri $csvUrl -UseBasicParsing
        $csvContent = $response.Content
        
        # Parse CSV (skip header row)
        $domains = @()
        $lines = $csvContent -split "`n" | Where-Object { $_.Trim() -ne "" }
        
        # Skip de header regel
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line) {
                # CSV kan verschillende kolommen hebben, neem de eerste kolom als domein
                $columns = $line -split ","
                if ($columns.Count -gt 0) {
                    $domain = $columns[0].Trim().Trim('"')
                    if ($domain -and $domain -match '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$') {
                        $domains += $domain
                    }
                }
            }
        }
        
        Write-Log "Succesvol $($domains.Count) domeinen opgehaald." -Level Success
        return $domains
    }
    catch {
        Write-Log "Fout bij ophalen van RMM-domeinen: $_" -Level Error
        return $null
    }
}

# Functie om bestaande block entries op te halen
function Get-ExistingBlockEntries {
    Write-Log "Ophalen van bestaande block entries..."
    
    try {
        $existingEntries = Get-TenantAllowBlockListItems -ListType Url -Block -ErrorAction Stop
        Write-Log "Succesvol $($existingEntries.Count) bestaande block entries opgehaald." -Level Success
        return $existingEntries
    }
    catch {
        Write-Log "Fout bij ophalen van bestaande block entries: $_" -Level Error
        return @()
    }
}

# Functie om domeinen toe te voegen aan block list
function Add-DomainsToBlockList {
    param(
        [string[]]$Domains,
        [array]$ExistingEntries
    )
    
    Write-Log "Toevoegen van domeinen aan Tenant Allow/Block List..."
    
    # Filter domeinen die al geblokkeerd zijn
    $existingDomains = $ExistingEntries | Where-Object { $_.Value } | Select-Object -ExpandProperty Value
    $newDomains = $Domains | Where-Object { $_ -notin $existingDomains }
    
    if ($newDomains.Count -eq 0) {
        Write-Log "Alle domeinen zijn al aanwezig in de block list." -Level Warning
        return @{
            TotalDomains = $Domains.Count
            AlreadyBlocked = $Domains.Count
            NewlyBlocked = 0
            Failed = 0
        }
    }
    
    Write-Log "Aantal domeinen die toegevoegd moeten worden: $($newDomains.Count)" -Level Info
    Write-Log "Aantal domeinen al geblokkeerd: $($Domains.Count - $newDomains.Count)" -Level Info
    
    if ($DryRun) {
        Write-Log "DRY RUN MODE - Geen wijzigingen worden doorgevoerd" -Level Warning
        Write-Log "Domeinen die toegevoegd zouden worden:" -Level Info
        $newDomains | ForEach-Object { Write-Log "  - $_" -Level Info }
        return @{
            TotalDomains = $Domains.Count
            AlreadyBlocked = $Domains.Count - $newDomains.Count
            NewlyBlocked = 0
            Failed = 0
            DryRun = $true
        }
    }
    
    # Toevoegen in batches van 20 (maximum per cmdlet call)
    $batchSize = 20
    $successCount = 0
    $failCount = 0
    
    for ($i = 0; $i -lt $newDomains.Count; $i += $batchSize) {
        $batch = $newDomains[$i..[Math]::Min($i + $batchSize - 1, $newDomains.Count - 1)]
        
        try {
            # Bepaal expiration parameters
            if ($NoExpiration) {
                New-TenantAllowBlockListItems -ListType Url -Block -Entries $batch -NoExpiration -Notes $Notes -ErrorAction Stop | Out-Null
            }
            else {
                $expirationDate = (Get-Date).AddDays($ExpirationDays)
                New-TenantAllowBlockListItems -ListType Url -Block -Entries $batch -ExpirationDate $expirationDate -Notes $Notes -ErrorAction Stop | Out-Null
            }
            
            $successCount += $batch.Count
            Write-Log "Batch van $($batch.Count) domeinen succesvol toegevoegd." -Level Success
        }
        catch {
            Write-Log "Fout bij toevoegen van batch: $_" -Level Warning
            Write-Log "Proberen om domeinen individueel toe te voegen..." -Level Info
            
            # Als batch faalt, probeer elk domein individueel
            foreach ($domain in $batch) {
                try {
                    if ($NoExpiration) {
                        New-TenantAllowBlockListItems -ListType Url -Block -Entries $domain -NoExpiration -Notes $Notes -ErrorAction Stop | Out-Null
                    }
                    else {
                        $expirationDate = (Get-Date).AddDays($ExpirationDays)
                        New-TenantAllowBlockListItems -ListType Url -Block -Entries $domain -ExpirationDate $expirationDate -Notes $Notes -ErrorAction Stop | Out-Null
                    }
                    
                    $successCount++
                    Write-Log "  ✓ Succesvol toegevoegd: $domain" -Level Success
                }
                catch {
                    $failCount++
                    Write-Log "  ✗ Gefaald: $domain - $_" -Level Error
                }
                
                # Kleine pauze tussen individuele toevoegingen
                Start-Sleep -Milliseconds 200
            }
        }
        
        # Kleine pauze tussen batches om rate limiting te voorkomen
        if ($i + $batchSize -lt $newDomains.Count) {
            Start-Sleep -Milliseconds 500
        }
    }
    
    return @{
        TotalDomains = $Domains.Count
        AlreadyBlocked = $Domains.Count - $newDomains.Count
        NewlyBlocked = $successCount
        Failed = $failCount
    }
}

# Hoofdprogramma
function Main {
    Write-Log "=== Start RMM Domains Blocker Script ===" -Level Info
    Write-Log "Logbestand: $logFile" -Level Info
    
    # Controleer en installeer Exchange Online module
    if (-not (Test-ExchangeOnlineModule)) {
        Write-Log "Kan niet doorgaan zonder Exchange Online Management module." -Level Error
        return
    }
    
    # Verbind met Exchange Online (alleen als niet in DryRun mode voor domein ophalen)
    if (-not $DryRun -or $true) {  # We hebben altijd een verbinding nodig om bestaande entries te controleren
        if (-not (Connect-ExchangeOnlineService)) {
            Write-Log "Kan niet doorgaan zonder Exchange Online verbinding." -Level Error
            return
        }
    }
    
    # Haal RMM-domeinen op
    $domains = Get-RMMDomains
    if (-not $domains -or $domains.Count -eq 0) {
        Write-Log "Geen domeinen gevonden om te blokkeren." -Level Error
        return
    }
    
    # Haal bestaande block entries op
    $existingEntries = Get-ExistingBlockEntries
    
    # Voeg domeinen toe aan block list
    $result = Add-DomainsToBlockList -Domains $domains -ExistingEntries $existingEntries
    
    # Rapportage
    Write-Log "`n=== Samenvatting ===" -Level Info
    Write-Log "Totaal aantal domeinen in LOLRMM lijst: $($result.TotalDomains)" -Level Info
    Write-Log "Al geblokkeerd: $($result.AlreadyBlocked)" -Level Info
    Write-Log "Nieuw toegevoegd: $($result.NewlyBlocked)" -Level Success
    if ($result.Failed -gt 0) {
        Write-Log "Gefaald: $($result.Failed)" -Level Error
    }
    if ($result.DryRun) {
        Write-Log "DRY RUN MODE - Geen wijzigingen doorgevoerd" -Level Warning
    }
    
    Write-Log "`nLogbestand: $logFile" -Level Info
    Write-Log "=== Script Voltooid ===" -Level Success
    
    # Verbreek verbinding
    if (-not $DryRun) {
        try {
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Verbinding met Exchange Online verbroken." -Level Info
        }
        catch {
            # Negeer errors bij disconnect
        }
    }
}

# Voer hoofdprogramma uit
Main
