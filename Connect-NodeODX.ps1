param([switch]$Setup)

$ErrorActionPreference = 'Stop'
$api = 'http://127.0.0.1:29301'
$tokenPath = Join-Path $env:LOCALAPPDATA 'AAV-NodeODX.token.xml'

if ($Setup) {
    $secureToken = Read-Host 'Enter the local NodeODX processing-node token' -AsSecureString
} else {
    if (-not (Test-Path -LiteralPath $tokenPath)) {
        throw 'Run Connect-NodeODX.ps1 -Setup first.'
    }
    $secureToken = Import-Clixml -LiteralPath $tokenPath
}

$credential = New-Object System.Management.Automation.PSCredential('nodeodx', $secureToken)
$encodedToken = [uri]::EscapeDataString($credential.GetNetworkCredential().Password)

try {
    $info = Invoke-RestMethod -Uri "$api/info?token=$encodedToken" -TimeoutSec 10 -MaximumRedirection 0
    $tasks = Invoke-RestMethod -Uri "$api/task/list?token=$encodedToken" -TimeoutSec 10 -MaximumRedirection 0
} catch {
    throw 'Could not connect to the local NodeODX service.'
}
if ($info.error -or $tasks.error) {
    throw 'NodeODX rejected the request. Check the processing-node token.'
}

if ($Setup) {
    $secureToken | Export-Clixml -LiteralPath $tokenPath
}
Write-Host "Connected to local NodeODX. Engine: $($info.engine) $($info.engineVersion)"
$tasks | Select-Object uuid, name, status
