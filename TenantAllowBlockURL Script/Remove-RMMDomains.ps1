<#
.SYNOPSIS
    Verwijdert RMM-domeinen uit de Microsoft 365 Tenant Allow/Block List

.DESCRIPTION
    Dit script haalt de lijst met RMM-domeinen op van lolrmm.io en verwijdert
    deze uit de Tenant Allow/Block List. Handig als je bepaalde RMM-tools
    toch wilt toestaan of als je de blokkering ongedaan wilt maken.

.PARAMETER Domains
    Specifieke domeinen om te verwijderen (optioneel). Indien niet opgegeven,
    worden alle domeinen van de lolrmm.io lijst verwijderd.

.PARAMETER RemoveAll
    Verwijdert ALLE domeinen van de lolrmm.io lijst uit de block list.

.PARAMETER DryRun
    Test de werking zonder daadwerkelijk domeinen te verwijderen.

.EXAMPLE
    .\Remove-RMMDomains.ps1 -DryRun
    Test welke domeinen verwijderd zouden worden

.EXAMPLE
    .\Remove-RMMDomains.ps1 -RemoveAll
    Verwijdert alle RMM-domeinen van lolrmm.io uit de block list

.EXAMPLE
    .\Remove-RMMDomains.ps1 -Domains "teamviewer.com","anydesk.com"
    Verwijdert alleen specifieke domeinen

.NOTES
    Versie: 1.0
    Auteur: GitHub Copilot
    Datum: 2026-05-07
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Domains,
    
    [Parameter(Mandatory = $false)]
    [switch]$RemoveAll,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Configuratie
$csvUrl = "https://lolrmm.io/api/rmm_domains.csv"
$logFile = "RMM-Domains-Removal-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Functie voor logging
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    Add-Content -Path $logFile -Value $logMessage
}

# Functie om RMM-domeinen op te halen
function Get-RMMDomains {
    Write-Log "Ophalen van RMM-domeinen van $csvUrl..."
    
    try {
        $response = Invoke-WebRequest -Uri $csvUrl -UseBasicParsing
        $csvContent = $response.Content
        
        $domains = @()
        $lines = $csvContent -split "`n" | Where-Object { $_.Trim() -ne "" }
        
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line) {
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

# Functie om Exchange Online verbinding te maken
function Connect-ExchangeOnlineService {
    Write-Log "Verbinding maken met Exchange Online..."
    
    try {
        $existingConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
        
        if ($existingConnection) {
            Write-Log "Er is al een actieve Exchange Online verbinding." -Level Success
            return $true
        }
        
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Log "Succesvol verbonden met Exchange Online." -Level Success
        return $true
    }
    catch {
        Write-Log "Fout bij verbinden met Exchange Online: $_" -Level Error
        return $false
    }
}

# Functie om domeinen te verwijderen
function Remove-DomainsFromBlockList {
    param(
        [string[]]$DomainsToRemove
    )
    
    Write-Log "Verzamelen van block entries om te verwijderen..."
    
    try {
        # Haal alle geblokkeerde URL entries op
        $allBlockedEntries = Get-TenantAllowBlockListItems -ListType Url -Block -ErrorAction Stop
        
        # Filter entries die overeenkomen met de te verwijderen domeinen
        $entriesToRemove = $allBlockedEntries | Where-Object { 
            $DomainsToRemove -contains $_.Value 
        }
        
        if ($entriesToRemove.Count -eq 0) {
            Write-Log "Geen overeenkomende entries gevonden in de block list." -Level Warning
            return @{
                Requested = $DomainsToRemove.Count
                Found = 0
                Removed = 0
                Failed = 0
            }
        }
        
        Write-Log "Gevonden $($entriesToRemove.Count) entries om te verwijderen." -Level Info
        
        if ($DryRun) {
            Write-Log "DRY RUN MODE - Geen wijzigingen worden doorgevoerd" -Level Warning
            Write-Log "Entries die verwijderd zouden worden:" -Level Info
            $entriesToRemove | ForEach-Object { 
                Write-Log "  - $($_.Value) (Entry ID: $($_.Identity))" -Level Info 
            }
            return @{
                Requested = $DomainsToRemove.Count
                Found = $entriesToRemove.Count
                Removed = 0
                Failed = 0
                DryRun = $true
            }
        }
        
        # Verwijder entries één voor één
        $successCount = 0
        $failCount = 0
        
        foreach ($entry in $entriesToRemove) {
            try {
                Remove-TenantAllowBlockListItems -ListType Url -Ids $entry.Identity -ErrorAction Stop
                Write-Log "Succesvol verwijderd: $($entry.Value)" -Level Success
                $successCount++
            }
            catch {
                Write-Log "Fout bij verwijderen van $($entry.Value): $_" -Level Error
                $failCount++
            }
            
            # Kleine pauze tussen verwijderingen
            Start-Sleep -Milliseconds 200
        }
        
        return @{
            Requested = $DomainsToRemove.Count
            Found = $entriesToRemove.Count
            Removed = $successCount
            Failed = $failCount
        }
    }
    catch {
        Write-Log "Fout bij verzamelen/verwijderen van entries: $_" -Level Error
        return @{
            Requested = $DomainsToRemove.Count
            Found = 0
            Removed = 0
            Failed = $DomainsToRemove.Count
        }
    }
}

# Hoofdprogramma
function Main {
    Write-Log "=== Start RMM Domains Removal Script ===" -Level Info
    Write-Log "Logbestand: $logFile" -Level Info
    
    # Validatie van parameters
    if (-not $RemoveAll -and -not $Domains) {
        Write-Log "Fout: Geef -RemoveAll op om alle LOLRMM domeinen te verwijderen, of specificeer domeinen via -Domains" -Level Error
        Write-Log "Voorbeeld: .\Remove-RMMDomains.ps1 -RemoveAll" -Level Info
        Write-Log "Voorbeeld: .\Remove-RMMDomains.ps1 -Domains 'teamviewer.com','anydesk.com'" -Level Info
        return
    }
    
    # Verbind met Exchange Online
    if (-not (Connect-ExchangeOnlineService)) {
        Write-Log "Kan niet doorgaan zonder Exchange Online verbinding." -Level Error
        return
    }
    
    # Bepaal welke domeinen te verwijderen
    $domainsToRemove = @()
    
    if ($RemoveAll) {
        Write-Log "RemoveAll opgegeven - ophalen van alle LOLRMM domeinen..." -Level Info
        $domainsToRemove = Get-RMMDomains
        if (-not $domainsToRemove -or $domainsToRemove.Count -eq 0) {
            Write-Log "Geen domeinen gevonden om te verwijderen." -Level Error
            return
        }
    }
    else {
        $domainsToRemove = $Domains
        Write-Log "Specifieke domeinen opgegeven: $($domainsToRemove.Count)" -Level Info
    }
    
    # Verwijder domeinen
    $result = Remove-DomainsFromBlockList -DomainsToRemove $domainsToRemove
    
    # Rapportage
    Write-Log "`n=== Samenvatting ===" -Level Info
    Write-Log "Opgevraagd om te verwijderen: $($result.Requested)" -Level Info
    Write-Log "Gevonden in block list: $($result.Found)" -Level Info
    Write-Log "Succesvol verwijderd: $($result.Removed)" -Level Success
    if ($result.Failed -gt 0) {
        Write-Log "Gefaald: $($result.Failed)" -Level Error
    }
    if ($result.DryRun) {
        Write-Log "DRY RUN MODE - Geen wijzigingen doorgevoerd" -Level Warning
    }
    
    Write-Log "`nLogbestand: $logFile" -Level Info
    Write-Log "=== Script Voltooid ===" -Level Success
    
    # Verbreek verbinding
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Verbinding met Exchange Online verbroken." -Level Info
    }
    catch {
        # Negeer errors bij disconnect
    }
}

# Voer hoofdprogramma uit
Main
