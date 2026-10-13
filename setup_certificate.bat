@echo off
setlocal enabledelayedexpansion
title Handheld Tools - Certificate Setup

:: Check Administrator Privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges to install code signing certificate...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   Handheld Tools - Authenticode Certificate Installer
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$certName = 'HandheldToolsSigner';" ^
    "$existing = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert | Where-Object { $_.Subject -match $certName };" ^
    "if ($existing) {" ^
    "    Write-Host '[*] Certificate HandheldToolsSigner already exists in LocalMachine\My.' -ForegroundColor Green;" ^
    "    $cert = $existing[0];" ^
    "} else {" ^
    "    Write-Host '[*] Creating new Self-Signed Code Signing Certificate (10 years)...' -ForegroundColor Cyan;" ^
    "    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject ('CN=' + $certName) -CertStoreLocation 'Cert:\LocalMachine\My' -KeySpec Signature -NotAfter (Get-Date).AddYears(10);" ^
    "    Write-Host '[OK] Certificate created with Thumbprint:' $cert.Thumbprint -ForegroundColor Green;" ^
    "};" ^
    "$rootStore = Get-Item Cert:\LocalMachine\Root;" ^
    "$rootStore.Open('ReadWrite');" ^
    "$inRoot = $rootStore.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint };" ^
    "if (-not $inRoot) {" ^
    "    $rootStore.Add($cert);" ^
    "    Write-Host '[OK] Added certificate to Trusted Root Certification Authorities (Root).' -ForegroundColor Green;" ^
    "} else {" ^
    "    Write-Host '[*] Certificate already present in Trusted Root store.' -ForegroundColor Yellow;" ^
    "};" ^
    "$rootStore.Close();" ^
    "$pubStore = Get-Item Cert:\LocalMachine\TrustedPublisher;" ^
    "$pubStore.Open('ReadWrite');" ^
    "$inPub = $pubStore.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint };" ^
    "if (-not $inPub) {" ^
    "    $pubStore.Add($cert);" ^
    "    Write-Host '[OK] Added certificate to Trusted Publishers store.' -ForegroundColor Green;" ^
    "} else {" ^
    "    Write-Host '[*] Certificate already present in Trusted Publishers store.' -ForegroundColor Yellow;" ^
    "};" ^
    "$pubStore.Close();" ^
    "Write-Host '`n========================================================' -ForegroundColor Cyan;" ^
    "Write-Host '  [SUCCESS] Code Signing Certificate setup is complete!' -ForegroundColor Green;" ^
    "Write-Host '========================================================' -ForegroundColor Cyan;"

echo.
timeout /t 3 >nul
exit /b 0
