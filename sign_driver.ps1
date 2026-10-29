<#
.SYNOPSIS
    Self-Sign patched driver files for Windows Test Mode.
.DESCRIPTION
    Creates or re-uses a Code-Signing Certificate 'nv_mod' and signs
    nvlddmkm.sys and the catalog file nv_disp.cat with SHA256.
.PARAMETER DriverDir
    Path to the 'Display.Driver' directory containing nvlddmkm.sys and nv_disp.cat.
.EXAMPLE
    .\sign_driver.ps1 -DriverDir "C:\NVIDIA\551.86\Display.Driver"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DriverDir
)

# 1. Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Please run this PowerShell script as Administrator!"
    exit 1
}

# 2. Find or Create Code Signing Certificate
$certSubject = "CN=nv_mod"
$cert = Get-ChildItem -Path Cert:\LocalMachine\My -CodeSigningCert | Where-Object { $_.Subject -eq $certSubject } | Select-Object -First 1

if (-not $cert) {
    Write-Host "[*] Creating new self-signed Code Signing Certificate '$certSubject'..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $certSubject -FriendlyName "nv_mod" -CertStoreLocation "Cert:\LocalMachine\My"
    
    # Export and import into Trusted Root and Publishers
    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $tempCertPath = "$env:TEMP\nv_mod_temp.cer"
    [System.IO.File]::WriteAllBytes($tempCertPath, $certBytes)

    Import-Certificate -FilePath $tempCertPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Import-Certificate -FilePath $tempCertPath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null
    Remove-Item -Force $tempCertPath
    Write-Host "[+] Certificate successfully installed into Root and TrustedPublisher stores." -ForegroundColor Green
} else {
    Write-Host "[+] Re-using existing certificate: $($cert.Thumbprint)" -ForegroundColor Green
}

# 3. Files to Sign
$filesToSign = @(
    (Join-Path $DriverDir "nvlddmkm.sys"),
    (Join-Path $DriverDir "nv_disp.cat")
)

foreach ($filePath in $filesToSign) {
    if (Test-Path $filePath) {
        Write-Host "[*] Signing: $filePath" -ForegroundColor Cyan
        $res = Set-AuthenticodeSignature -FilePath $filePath -Certificate $cert -HashAlgorithm SHA256
        if ($res.Status -eq "Valid") {
            Write-Host "    [OK] Signature Status: Valid" -ForegroundColor Green
        } else {
            Write-Warning "    [!] Warning: Status is $($res.Status) - $($res.StatusMessage)"
        }
    } else {
        Write-Warning "[-] File not found: $filePath"
    }
}

Write-Host "`n[+] Driver signing process completed." -ForegroundColor Green
