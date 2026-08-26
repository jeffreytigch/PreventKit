# Supply Chain Security

This document describes the supply chain security posture of the PreventKit module and guidance for secure deployment.

## External Dependencies

PreventKit has minimal external dependencies by design:

| Dependency | Type | Risk Level | Mitigation |
|------------|------|------------|------------|
| PowerShell 7+ | Runtime | Low | Microsoft-signed, built-in |
| ExchangeOnlineManagement | Module (TABL) | Low | Microsoft first-party, signed |
| Azure CLI (`az`) | Binary (CNI auto) | Medium | Verify signature, pin version |
| Microsoft Defender API | Service | Low | Microsoft first-party, TLS 1.2+ |

## Module Integrity

### No External Module Dependencies

The `PreventKit.psd1` manifest declares **zero** `RequiredModules`. All functionality is self-contained within the module. This eliminates the risk of transitive dependency compromise from the PowerShell Gallery.

### No Code Download/Execution

The module never:
- Downloads and executes scripts (`Invoke-Expression`, `iex`)
- Downloads files for execution (`Invoke-WebRequest` + `Invoke-Expression`)
- Installs modules at runtime (`Install-Module`)
- Loads assemblies from untrusted paths

### Catalogue Sources

Catalogue sources are user-controlled:
- Local files: No supply chain risk
- HTTPS URLs: User must trust the source; module validates TLS certificates

**Recommendation**: Host catalogue sources in your own version-controlled repository (GitHub, Azure DevOps, etc.) and reference local paths in catalogue declarations.

## Verification Steps

### 1. Verify Module Signature

```powershell
# Check if module is signed
Get-AuthenticodeSignature -FilePath ./src/PreventKit/PreventKit.psd1
```

### 2. Verify File Integrity

```powershell
# Generate SHA-256 hashes of all module files
Get-ChildItem ./src/PreventKit -Recurse -File | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    "$($hash.Hash)  $($_.FullName)"
}
```

Store these hashes in your secure deployment pipeline and verify on each deployment.

### 3. Pin Azure CLI Version

In your deployment pipeline, pin the Azure CLI version:

```yaml
# Azure Pipelines example
- task: AzureCLI@2
  inputs:
    azureSubscription: 'your-subscription'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az version
      # Pin to specific version if needed
      # az upgrade --version 2.53.0
```

### 4. Restrict Network Access

The module only connects to:
- `https://api.security.microsoft.com` (CNI API)
- `https://api.securitycenter.microsoft.com` (Token resource)
- `https://login.microsoftonline.com` (Azure AD token endpoint)
- User-specified catalogue HTTPS URLs

Configure egress firewall rules to allow only these destinations.

## Secure Deployment Checklist

- [ ] Module files hash-verified against known-good values
- [ ] Module signature verified (if signed)
- [ ] Azure CLI version pinned in deployment pipeline
- [ ] Catalogue sources hosted in version-controlled, access-controlled repository
- [ ] Egress firewall rules restrict to documented endpoints
- [ ] Service principal / managed identity used for scheduled runs (not interactive user)
- [ ] Run logs stored in write-once / append-only storage
- [ ] Module deployed via approved pipeline (not manual copy)

## Threat Model

| Threat | Likelihood | Impact | Mitigation |
|--------|------------|--------|------------|
| Compromised Azure CLI | Low | High | Pin version, verify signature, use managed identity instead |
| Compromised catalogue source | Medium | High | Host in private repo, validate content hashes |
| Module tampering in transit | Low | High | Verify hashes, use signed modules, deploy via pipeline |
| Malicious catalogue declaration | Low | Medium | Review declarations in PR, validate adapter allowlist |
| Dependency confusion | None | N/A | No external module dependencies |

## Reporting Security Issues

Report security vulnerabilities privately to the maintainers. Do not open public issues for security concerns.