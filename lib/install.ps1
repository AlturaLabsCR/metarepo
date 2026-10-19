[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._+-]*$')]
    [string]$Package,
    [string]$Version,
    [string]$PackageRelease,
    [string]$Release = 'windows11',
    [ValidateSet('x86', 'x64', 'arm64')]
    [string]$Architecture,
    [ValidateSet('Machine', 'User')]
    [string]$Scope = 'Machine',
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = @REPO_ROOT_PS@
$Channels = ConvertFrom-Json -InputObject @CHANNELS_PS@

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This installer requires Windows.'
}
# Default selector is for Windows 11 workstations, not Windows Server.
if ($Release -eq 'windows11') {
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 22000) {
        throw 'The windows11 release requires a Windows 11 workstation.'
    }
}
if (-not $Architecture) {
    $nativeArchitecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $nativeArchitecture) { $nativeArchitecture = $env:PROCESSOR_ARCHITECTURE }
    $Architecture = switch ($nativeArchitecture) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        'x86' { 'x86' }
        default { throw "Unsupported Windows architecture: $nativeArchitecture" }
    }
}
$channelMatches = @($Channels | Where-Object { $_.selectors -contains $Release })
if ($channelMatches.Count -ne 1) { throw "Unknown MSI release or channel: $Release" }
$channel = $channelMatches[0].name
$baseUri = [Uri]($RepositoryRoot.TrimEnd('/') + '/')
if ($baseUri.Scheme -ne 'https') { throw 'The Windows installer requires an HTTPS repository URL.' }
# Windows PowerShell 5.1 may otherwise negotiate older TLS defaults.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$catalog = Invoke-RestMethod -Uri ([Uri]::new($baseUri, "$channel/catalog.json"))
if ($catalog.schemaVersion -ne 1) { throw 'Unsupported MSI catalog schema.' }
$candidates = @($catalog.packages | Where-Object {
    $_.name -eq $Package -and $_.architecture -eq $Architecture -and
    (-not $Version -or $_.version -eq $Version) -and
    (-not $PackageRelease -or $_.release -eq $PackageRelease)
})
if ($candidates.Count -eq 0) { throw 'No matching MSI. Check package, version, release and architecture.' }
if ($candidates.Count -ne 1) {
    $available = ($candidates | ForEach-Object { "$($_.version) (release $($_.release))" }) -join ', '
    throw "Several MSI versions match: $available. Specify -Version and, if needed, -PackageRelease."
}
$entry = $candidates[0]
if ($entry.file -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._+-]*\.msi$' -or
    $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'Invalid MSI catalog entry.'
}
if (-not $PSCmdlet.ShouldProcess("$Package $($entry.version) ($Architecture), scope $Scope", 'Install MSI')) { return }
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporaryDirectory
$installer = Join-Path $temporaryDirectory 'installer.msi'
# Keep the log after the downloaded MSI is cleaned up.
$log = Join-Path ([IO.Path]::GetTempPath()) ("msi-" + [Guid]::NewGuid().ToString('N') + '.log')
try {
    Invoke-WebRequest -UseBasicParsing -Uri ([Uri]::new($baseUri, "$channel/$($entry.file)")) -OutFile $installer
    if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw 'MSI SHA-256 verification failed. Installation was not started.'
    }
    $arguments = @('/i', ('"' + $installer + '"'), '/norestart', '/L*v', ('"' + $log + '"'))
    if ($Silent) { $arguments += '/qn' }
    if ($Scope -eq 'User') {
        # Only works for MSI packages authored to support per-user installation.
        $arguments += @('ALLUSERS=2', 'MSIINSTALLPERUSER=1')
    } else {
        $arguments += 'ALLUSERS=1'
    }
    $start = @{
        FilePath = (Join-Path $env:SystemRoot 'System32\msiexec.exe')
        ArgumentList = $arguments
        Wait = $true
        PassThru = $true
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($Scope -eq 'Machine' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $start.Verb = 'RunAs'
    }
    $process = Start-Process @start
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "MSI installation failed with code $($process.ExitCode). Log: $log"
    }
    Write-Host "Installed $Package $($entry.version). Log: $log"
    if ($process.ExitCode -in @(3010, 1641)) { Write-Warning 'Windows Installer reported that a restart is required.' }
} finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
}
