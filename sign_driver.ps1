<#
.SYNOPSIS
    Creates (if needed) a self-signed code-signing certificate, trusts it, and
    signs a patched nvlddmkm.sys plus its matching .cat file so Windows Test
    Mode will load it.

.PARAMETER DriverDir
    Folder containing the patched nvlddmkm.sys and the driver's .cat file
    (e.g. the extracted "Display.Driver" folder from the NVIDIA installer).

.PARAMETER CertSubject
    Common name for the self-signed certificate. Defaults to "nv_mod". Only
    needs to be changed if you already use that name for something else.

.EXAMPLE
    .\sign_driver.ps1 -DriverDir "Display.Driver"

Requires: Administrator PowerShell, Windows Test Mode enabled
(bcdedit /set testsigning on, then reboot) before the signed driver will load.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DriverDir,

    [string]$CertSubject = "nv_mod"
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

if (-not (Test-Path $DriverDir)) {
    Write-Error "DriverDir not found: $DriverDir"
    exit 1
}

$sysFile = Join-Path $DriverDir "nvlddmkm.sys"
if (-not (Test-Path $sysFile)) {
    Write-Error "nvlddmkm.sys not found in $DriverDir"
    exit 1
}

$catFile = Get-ChildItem -Path $DriverDir -Filter "*.cat" | Select-Object -First 1
if (-not $catFile) {
    Write-Warning "No .cat file found in $DriverDir — skipping catalog signing. " +
                   "The driver package may still fail installation if Windows checks the catalog."
}

# --- 1. Find or create the signing certificate ---
$cert = Get-ChildItem -Path Cert:\LocalMachine\My |
    Where-Object { $_.Subject -eq "CN=$CertSubject" } |
    Select-Object -First 1

if (-not $cert) {
    Write-Host "[+] No existing '$CertSubject' certificate found, creating one..."
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=$CertSubject" `
        -FriendlyName $CertSubject `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddYears(10)
    Write-Host "[+] Created certificate, thumbprint: $($cert.Thumbprint)"
} else {
    Write-Host "[+] Reusing existing '$CertSubject' certificate, thumbprint: $($cert.Thumbprint)"
}

# --- 2. Trust it (Root + Trusted Publishers), no manual certlm.msc needed ---
foreach ($storeName in @("Root", "TrustedPublisher")) {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
        $storeName, "LocalMachine")
    $store.Open("ReadWrite")
    if (-not ($store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })) {
        $store.Add($cert)
        Write-Host "[+] Added certificate to LocalMachine\$storeName"
    } else {
        Write-Host "[i] Certificate already present in LocalMachine\$storeName"
    }
    $store.Close()
}

# --- 3. Sign the driver ---
Write-Host "`n[+] Signing $sysFile ..."
$result = Set-AuthenticodeSignature -FilePath $sysFile -Certificate $cert -HashAlgorithm SHA256
Write-Host "    Status: $($result.Status)"
if ($result.Status -ne "Valid") {
    Write-Error "Signing nvlddmkm.sys did not report Valid (got: $($result.Status))."
    exit 1
}

if ($catFile) {
    Write-Host "[+] Signing $($catFile.FullName) ..."
    $catResult = Set-AuthenticodeSignature -FilePath $catFile.FullName -Certificate $cert -HashAlgorithm SHA256
    Write-Host "    Status: $($catResult.Status)"
    if ($catResult.Status -ne "Valid") {
        Write-Error "Signing the .cat file did not report Valid (got: $($catResult.Status))."
        exit 1
    }
}

Write-Host "`n[+] Done. Certificate thumbprint used: $($cert.Thumbprint)"
Write-Host "    Make sure Windows Test Mode is enabled (bcdedit /set testsigning on, then reboot)"
Write-Host "    and Secure Boot / HVCI are disabled before installing the driver."
