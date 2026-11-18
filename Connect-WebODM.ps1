param(
    [switch]$Setup,
    [string]$ProjectName = 'R Final Project - UAV Mapping Baseline'
)

$ErrorActionPreference = 'Stop'
$api = 'http://127.0.0.1:29800/api'
$credentialPath = Join-Path $env:LOCALAPPDATA 'AAV-WebODM.credential.xml'

if ($Setup) {
    $credential = Get-Credential -Message 'Enter the dedicated local WebODM account.'
    if (-not $credential) { return }
} else {
    if (-not (Test-Path -LiteralPath $credentialPath)) {
        throw 'Run Connect-WebODM.ps1 -Setup in Windows PowerShell first.'
    }
    $credential = Import-Clixml -LiteralPath $credentialPath
}

try {
    $session = Invoke-RestMethod -Uri "$api/token-auth/" -Method Post -Body @{
        username = $credential.UserName
        password = $credential.GetNetworkCredential().Password
    } -MaximumRedirection 0 -TimeoutSec 20
} catch {
    throw 'WebODM login failed. Check that the desktop app is running and the account can sign in.'
}
if (-not $session.token) { throw 'WebODM did not return an API token.' }

$headers = @{ Authorization = "JWT $($session.token)" }
$projects = Invoke-RestMethod -Uri "$api/projects/" -Headers $headers -MaximumRedirection 0 -TimeoutSec 20
if ($projects.PSObject.Properties['results']) { $projects = $projects.results }
$matches = @($projects | Where-Object { $_.name -eq $ProjectName })
if ($matches.Count -ne 1) {
    throw "Expected one accessible WebODM project named '$ProjectName'. Check the name and project permissions."
}
$projectId = $matches[0].id
$tasks = Invoke-RestMethod -Uri "$api/projects/$projectId/tasks/" -Headers $headers -MaximumRedirection 0 -TimeoutSec 20
if ($tasks.PSObject.Properties['results']) { $tasks = $tasks.results }

if ($Setup) {
    $credential | Export-Clixml -LiteralPath $credentialPath
    Write-Host 'Saved the credential for this Windows account.'
}
Write-Host "Connected to WebODM project '$ProjectName' (ID $projectId)."
$tasks | Select-Object id, name, images_count, status, processing_time, available_assets
