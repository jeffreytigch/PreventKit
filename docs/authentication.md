# Authentication setup

PreventKit reconciles two enforcement targets, each with its own
authentication:

- **Custom Network Indicators (CNI)** calls the Microsoft Defender for Endpoint
  API at `api.security.microsoft.com`. Every request carries an
  `Authorization: Bearer <token>` header. Selecting CNI (via `-Target Cni`)
  automatically configures the target: the Run uses a caller-supplied
  `-CniToken` when provided, otherwise it acquires one from the signed-in
  Azure CLI session (`az account get-access-token --resource
  'https://api.securitycenter.microsoft.com'`). A Run with no token (no
  `-CniToken` and Azure CLI unavailable or not signed in) fails before any
  request is sent.
- **Tenant Allow/Block List (TABL)** writes through Exchange Online PowerShell
  cmdlets (`New-TenantAllowBlockListItems`, `Remove-TenantAllowBlockListItems`).
  These require a **connected Exchange Online session**
  (`Connect-ExchangeOnline`) in the same PowerShell session before the Run
  starts. There is no token parameter for TABL.

This page covers both targets: how to register an app in Microsoft Entra ID and
acquire a CNI token with the interactive, client certificate, and managed
identity flows, and how to prepare Exchange Online for a TABL Run.

## Least privilege at a glance

| Target | Interactive | App registration / managed identity |
| --- | --- | --- |
| CNI | Delegated `Ti.ReadWrite`, plus built-in **Security Administrator** (or a Defender XDR RBAC role with **Detection tuning → Manage**) | Application `Ti.ReadWrite.All` (no directory role) |
| TABL | Exchange **Security Operator** role group, or built-in **Exchange Administrator** | Office 365 Exchange Online `Exchange.ManageAsApp` plus a supported Microsoft Entra role |

Setup references:

- CNI app registration: [Create an app to access Microsoft Defender for Endpoint without a user](https://learn.microsoft.com/defender-endpoint/api/exposed-apis-create-app-webapp) — application context also supports a managed identity or certificate credential.
- CNI roles: [Assign Microsoft Entra roles](https://learn.microsoft.com/entra/identity/role-based-access-control/manage-roles-portal) and [Microsoft Defender unified RBAC](https://learn.microsoft.com/defender-xdr/manage-rbac).
- TABL app-only: [App-only authentication for unattended scripts in Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2).
- TABL managed identity: [Use Azure managed identities to connect to Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/connect-exo-powershell-managed-identity).
- TABL role permissions: [Permissions in Exchange Online](https://learn.microsoft.com/exchange/permissions-exo/permissions-exo).

## The MDE Custom Network Indicators API

| Fact | Value |
| --- | --- |
| API base | `https://api.security.microsoft.com` |
| Import endpoint | `POST /api/indicators/import` |
| Batch delete endpoint | `POST /api/indicators/BatchDelete` |
| Token resource / scope | `https://api.securitycenter.microsoft.com/.default` |
| Application permission | `Ti.ReadWrite.All` (Read and write All Indicators) |
| Delegated permission | `Ti.ReadWrite` (Read and write Indicators) |

The Custom Network Indicators feature must be enabled in the tenant:
**Microsoft Defender XDR** → **Settings** → **Endpoints** → **Advanced
features** → **Custom network indicators**.

## Step 1 — Register the application

1. Sign in to the [Azure portal](https://portal.azure.com).
2. Go to **Microsoft Entra ID** → **App registrations** → **New registration**.
3. Enter a name for the application (for example `PreventKit`).
4. For **Supported account types**, choose **Accounts in this organizational
   directory only** (single tenant) unless you are building a multi-tenant app.
5. Leave the redirect URI empty for app-only flows. For the interactive flow
   you will add a **Mobile and desktop applications** platform with the
   `http://localhost` redirect URI instead.
6. Select **Register** and record the **Application (client) ID** and
   **Directory (tenant) ID** from the **Overview** page.

## Step 2 — Add API permissions and grant admin consent

1. In the app registration, go to **Manage** → **API permissions** →
   **Add a permission**.
2. Switch to the **APIs my organization uses** tab and search for
   **WindowsDefenderATP**. The Defender for Endpoint API does not appear in the
   default **Microsoft APIs** list — you must type its name to find it.
3. Select the permission type and scope for the flow you will use:

   | Flow | Permission type | Permission |
   | --- | --- | --- |
   | Interactive (delegated) | Delegated permissions | `Ti.ReadWrite` |
   | Client certificate | Application permissions | `Ti.ReadWrite.All` |
   | Managed identity | Application permissions | `Ti.ReadWrite.All` |

4. Select **Add permissions**.
5. On the same page, select **Grant admin consent** and confirm. The
   `Ti.ReadWrite.All` application permission and the `Ti.ReadWrite` delegated
   permission both require tenant-wide admin consent.

`Ti.ReadWrite.All` is the least-privileged application permission that supports
every call PreventKit makes: the narrower `Ti.ReadWrite` application permission
does not cover the import and batch-delete endpoints, and only exposes
indicators the app itself created. For an app registration or managed identity,
follow Microsoft's [application context setup](https://learn.microsoft.com/defender-endpoint/api/exposed-apis-create-app-webapp),
which supports a managed identity or certificate credential. App-only access is
granted entirely by this application permission, so do not attach a Microsoft
Entra directory role to the CNI app or managed identity.

## Step 3 — Acquire a token

When CNI is selected without `-CniToken`, PreventKit acquires a token
automatically from the signed-in Azure CLI session. Supplying `-CniToken`
skips that acquisition (verification and the current-entry read still happen).
Any token for the `https://api.securitycenter.microsoft.com` resource works —
pick the flow that fits how the Run is invoked. All three flows below produce
a token you can pass as `-CniToken`.

### Interactive (delegated) flow

Best for **manual Runs** from an operator's machine. The signed-in user must
hold a Defender for Endpoint role that can manage indicators (in the Defender
portal RBAC model, this is the **Indicators (manage)** permission under
**Security operations**; in the unified RBAC model, **Detection tuning →
Manage**). If the user can manage indicators in the portal, the same user can
manage them through the API with the `Ti.ReadWrite` delegated scope.

The user also needs access to Defender for Endpoint itself. The
least-privileged built-in Microsoft Entra role with write access is **Security
Administrator** (**Security Reader** is read-only). For tighter scoping, assign
a [Microsoft Defender unified RBAC](https://learn.microsoft.com/defender-xdr/manage-rbac)
role carrying **Detection tuning → Manage** instead of the broader Entra role.
Grant the role with [Assign Microsoft Entra roles](https://learn.microsoft.com/entra/identity/role-based-access-control/manage-roles-portal).

Acquire the token with [Microsoft Authentication Library
(MSAL)](https://learn.microsoft.com/en-us/entra/msal/dotnet/) or the Azure CLI:

```powershell
az login --tenant 'your-tenant-id'
$token = (az account get-access-token --resource 'https://api.securitycenter.microsoft.com' | ConvertFrom-Json).accessToken

Invoke-PreventKitRun -CatalogueDirectory ./catalogues -Target Cni -CniToken $token
```

The interactive flow prompts in a browser, so it is not suitable for unattended
scheduled Runs.

### App-only client certificate flow

Best for **scheduled Runs**: the Run authenticates as the registered app with
no signed-in user, so nothing depends on a person's session.

**Generate the certificate on macOS** with `openssl`:

```powershell
# Create a self-signed certificate (private key + public certificate).
openssl req -new -x509 -newkey rsa:2048 -keyout preventkit.key -out preventkit.crt `
  -days 365 -nodes -subj '/CN=PreventKit'

# Export the private key as a PFX/PKCS#12 for the token request.
openssl pkcs12 -export -out preventkit.pfx -inkey preventkit.key -in preventkit.crt `
  -passout pass:'<a-strong-passphrase>'
```

Upload the **public certificate** (`preventkit.crt`) to the app registration:

1. In the app registration, go to **Manage** → **Certificates & secrets** →
   **Certificates** → **Upload certificate**.
2. Select `preventkit.crt`, add a description, and select **Add**.
3. Record the **Thumbprint** shown for the uploaded certificate.

Acquire the token using the certificate as the client credential:

```powershell
$tenantId = '<tenant-id>'
$appId = '<application-client-id>'
$pfxPath = './preventkit.pfx'
$pfxPass = '<a-strong-passphrase>'

# Load the private key for the client assertion.
$cert = Get-PfxCertificate -FilePath $pfxPath

# Sign a client assertion JWT with the certificate's private key.
$now = [int][double]::Parse((Get-Date -UFormat %s))
$notBefore = $now - 60
$notAfter = $now + 300
$header = @{ alg = 'RS256'; x5t = $cert.Thumbprint } | ConvertTo-Json -Compress
$payload = @{
    aud   = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    iss   = $appId
    sub   = $appId
    jti   = [guid]::NewGuid().Guid
    nbf   = $notBefore
    exp   = $notAfter
} | ConvertTo-Json -Compress

$base64UrlEncode = {
    param([byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
$segments = @(
    & $base64UrlEncode ([Text.Encoding]::UTF8.GetBytes($header))
    & $base64UrlEncode ([Text.Encoding]::UTF8.GetBytes($payload))
)
$signatureInput = $segments -join '.'
$signatureBytes = $cert.PrivateKey.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$clientAssertion = "$signatureInput.$( & $base64UrlEncode $signatureBytes )"

$authBody = [ordered]@{
    scope                 = 'https://api.securitycenter.microsoft.com/.default'
    client_id             = $appId
    client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
    client_assertion      = $clientAssertion
    grant_type            = 'client_credentials'
}

$authResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -Body $authBody
$token = $authResponse.access_token

Invoke-PreventKitRun -CatalogueDirectory ./catalogues -Target Cni -CniToken $token
```

Keep the passphrase-protected private key out of the repository. For a
scheduled Run, store it in a location the scheduler can read without a human
present (for example a Key Vault secret or the service account's certificate
store), and rotate the certificate before it expires.

### Managed identity flow

Where the Run runs on an Azure resource (for example an Azure VM or Azure
Functions app), you can use that resource's **managed identity** instead of a
certificate — no secret or key to store and rotate.

Whether the MDE API accepts a managed-identity token depends on the tenant's
setup: the managed identity's service principal must hold the application
permission the API checks (`Ti.ReadWrite.All` on the WindowsDefenderATP
resource), which your tenant administrator grants. Microsoft's [application
context guidance](https://learn.microsoft.com/defender-endpoint/api/exposed-apis-create-app-webapp)
lists managed identity as a supported credential alongside client certificates,
but validate it against your tenant before relying on it for a scheduled Run.

To acquire the token with a managed identity from PowerShell running on the
Azure resource:

```powershell
$token = (Invoke-RestMethod -Method Get -Headers @{
    Metadata = 'true'
} -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fapi.securitycenter.microsoft.com').access_token

Invoke-PreventKitRun -CatalogueDirectory ./catalogues -Target Cni -CniToken $token
```

If the Run does not run on an Azure resource, use the client certificate flow
instead.

## Which flow for which Run

| Run type | Recommended flow | Why |
| --- | --- | --- |
| Manual | Interactive (delegated) | Operator signs in once; no key material to store |
| Scheduled, no Azure | App-only client certificate | Authenticates as the app, no human session needed |
| Scheduled, on Azure | Managed identity | No secret to store or rotate; app permission only |
| Any | Any (or omit `-CniToken` for automatic Azure CLI acquisition) | An explicit `-CniToken` overrides automatic acquisition |

## Supplying the token to a Run

The token is resolved at **Run time**: pass `-CniToken` to use an explicit
token supplied by the caller, or omit it to acquire one automatically from the signed-in Azure CLI
session. A manual Run passes it as `-CniToken` to `Invoke-PreventKitRun`; the
scheduled wrapper accepts the same `-CniToken` parameter. A Run that selects
Custom Network Indicators with no token available (no `-CniToken` and Azure
CLI unavailable or not signed in) fails before any request is sent.

Automatic acquisition needs the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
installed and signed in (`az login`, using `--tenant` in a multi-tenant
environment). It acquires a fresh token for every Run. A token you supply
yourself expires (typically within an hour), so for unattended Runs prefer the
client certificate or managed identity flow, which acquires its token at Run
time rather than caching one.

## TABL authentication

The Tenant Allow/Block List target writes through Exchange Online PowerShell.
It has no token parameter: you prepare a session before the Run, in the same
PowerShell session the Run uses.

### Prerequisite: the ExchangeOnlineManagement module

TABL depends on the first-party [`ExchangeOnlineManagement`](https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2)
module, which is not a dependency of PreventKit. Install it once:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

A Run that selects TABL verifies the session by calling
`Get-TenantAllowBlockListItems` and writes with
`New-TenantAllowBlockListItems` and `Remove-TenantAllowBlockListItems`, so the
connected session must expose all three.

### Interactive Runs

Connect with an admin account before the Run:

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com
Invoke-PreventKitRun -CatalogueDirectory ./catalogues -Target Tabl
```

The account needs permission to add and remove Tenant Allow/Block List entries.
The most granular option is the Exchange **Security Operator** role group, which
carries the **Tenant AllowBlockList Manager** role (assign it directly in the
[Exchange admin center](https://admin.exchange.microsoft.com) under **Roles** >
**Admin Roles**). If you prefer a built-in Microsoft Entra role, the
least-privileged default is **Exchange Administrator**. Avoid Global
Administrator. See [Permissions in Exchange Online](https://learn.microsoft.com/exchange/permissions-exo/permissions-exo).

### Unattended Runs: app-only certificate or managed identity

For scheduled Runs, connect the session as an app or managed identity instead of
a person:

```powershell
# App-only certificate
Connect-ExchangeOnline -CertificateThumbprint '<thumbprint>' -AppId '<client-id>' -Organization 'contoso.onmicrosoft.com'

# Managed identity, from the Azure resource
Connect-ExchangeOnline -ManagedIdentity -Organization 'contoso.onmicrosoft.com'
```

The app or managed identity needs:

- the **Office 365 Exchange Online** > **`Exchange.ManageAsApp`** application
  permission, granted tenant-wide admin consent. It is the only Exchange Online
  PowerShell application permission, so it is the least-privileged permission
  that works; and
- a supported Microsoft Entra role assignment. The least-privileged default is
  **Exchange Administrator**.

Microsoft's setup guides cover both: [App-only authentication for unattended
scripts](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2)
and [Use Azure managed identities to connect to Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/connect-exo-powershell-managed-identity).
