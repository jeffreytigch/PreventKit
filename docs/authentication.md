# Authentication setup

PreventKit reconciles two enforcement targets, each with its own
authentication:

- **Custom Network Indicators (CNI)** calls the Microsoft Defender for Endpoint
  API at `api.security.microsoft.com`. Every request carries an
  `Authorization: Bearer <token>` header. The token is **supplied by the caller
  at Run time** — PreventKit never acquires it itself, so any acquisition
  method works.
- **Tenant Allow/Block List (TABL)** writes through Exchange Online PowerShell
  cmdlets (`New-TenantAllowBlockListItems`, `Remove-TenantAllowBlockListItems`).
  These require a **connected Exchange Online session**
  (`Connect-ExchangeOnline`) in the same PowerShell session before the Run
  starts. There is no token parameter for TABL.

This page covers the CNI token: how to register an app in Microsoft Entra ID,
what permissions each flow needs, and how to acquire a token with the
interactive, client certificate, and managed identity flows.

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

## Step 3 — Acquire a token

PreventKit accepts any token for the `https://api.securitycenter.microsoft.com`
resource. Pick the flow that fits how the Run is invoked. All three produce a
token you pass to the Run as `-CniToken`.

### Interactive (delegated) flow

Best for **manual Runs** from an operator's machine. The signed-in user must
hold a Defender for Endpoint role that can manage indicators (in the Defender
portal RBAC model, this is the **Indicators (manage)** permission under
**Security operations**; in the unified RBAC model, **Detection tuning →
Manage**). If the user can manage indicators in the portal, the same user can
manage them through the API with the `Ti.ReadWrite` delegated scope.

Acquire the token with [Microsoft Authentication Library
(MSAL)](https://learn.microsoft.com/en-us/entra/msal/dotnet/) or the Azure CLI:

```powershell
az login --tenant 'your-tenant-id'
$token = (az account get-access-token --resource 'https://api.securitycenter.microsoft.com' | ConvertFrom-Json).accessToken

Invoke-PreventKitRun -CatalogueDirectory ./catalogues -CniCapacity 15000 -CniToken $token
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

Invoke-PreventKitRun -CatalogueDirectory ./catalogues -CniCapacity 15000 -CniToken $token
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
resource), which your tenant administrator grants. Microsoft's app-only API
guidance lists managed identity as a supported credential alongside client
certificates, but validate it against your tenant before relying on it for a
scheduled Run.

To acquire the token with a managed identity from PowerShell running on the
Azure resource:

```powershell
$token = (Invoke-RestMethod -Method Get -Headers @{
    Metadata = 'true'
} -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fapi.securitycenter.microsoft.com').access_token

Invoke-PreventKitRun -CatalogueDirectory ./catalogues -CniCapacity 15000 -CniToken $token
```

If the Run does not run on an Azure resource, use the client certificate flow
instead.

## Which flow for which Run

| Run type | Recommended flow | Why |
| --- | --- | --- |
| Manual | Interactive (delegated) | Operator signs in once; no key material to store |
| Scheduled, no Azure | App-only client certificate | Authenticates as the app, no human session needed |
| Scheduled, on Azure | Managed identity | No secret to store or rotate; app permission only |
| Any | Any | The token is always supplied by the caller at Run time |

## Supplying the token to a Run

The token is supplied by the caller at **Run time** — it is not stored by
PreventKit and no acquisition method is baked into the module. A manual Run
passes it as `-CniToken` to `Invoke-PreventKitRun`; the scheduled wrapper
accepts the same `-CniToken` parameter. A Run that reconciles Custom Network
Indicators without a token fails before any request is sent.

For the Tenant Allow/Block List target, authentication is separate:
connect an Exchange Online session (`Connect-ExchangeOnline`) before the Run,
then pass `-TablCapacity` as usual.
