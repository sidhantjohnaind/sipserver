@echo off
title JioFiber B2BUA - Native TLS Certificate Generator
cd /d "%~dp0"

echo =====================================================================
echo    JioFiber B2BUA - Native TLS Certificate Generator (Zero Python)
echo =====================================================================
echo.

if not exist "certs" mkdir certs

where openssl >nul 2>&1
if %errorlevel% equ 0 (
    echo [*] Generating TLS Certificates via native OpenSSL...
    openssl genrsa -out certs\key.pem 2048 >nul 2>&1
    openssl req -x509 -new -nodes -key certs\key.pem -sha256 -days 3650 -out certs\cert.pem -subj "/C=IN/O=JioB2BUA/CN=192.168.29.195" >nul 2>&1
    copy certs\cert.pem certs\cert.crt >nul 2>&1
    openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -in certs\cert.pem -inkey certs\key.pem -out certs\cert.p12 -passout pass:1234 >nul 2>&1
    copy certs\cert.p12 certs\cert.pfx >nul 2>&1
    copy certs\* . >nul 2>&1
    goto :done
)

echo [*] Generating TLS Certificates via Windows PowerShell .NET Cryptography...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rsa = [System.Security.Cryptography.RSA]::Create(2048); $req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest('CN=192.168.29.195, O=JioB2BUA, C=IN', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1); $san = New-Object System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder; $san.AddIpAddress([System.Net.IPAddress]::Parse('192.168.29.195')); $san.AddIpAddress([System.Net.IPAddress]::Parse('127.0.0.1')); $san.AddDnsName('localhost'); $san.AddDnsName('JioFiberB2BUA'); $req.CertificateExtensions.Add($san.Build()); $cert = $req.CreateSelfSigned((Get-Date), (Get-Date).AddYears(10)); [System.IO.File]::WriteAllText('certs\cert.pem', ('-----BEGIN CERTIFICATE-----`r`n' + [System.Convert]::ToBase64String($cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), 'InsertLineBreaks') + '`r`n-----END CERTIFICATE-----`r`n')); [System.IO.File]::WriteAllText('certs\key.pem', ('-----BEGIN PRIVATE KEY-----`r`n' + [System.Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey(), 'InsertLineBreaks') + '`r`n-----END PRIVATE KEY-----`r`n')); Copy-Item 'certs\cert.pem' 'certs\cert.crt' -Force; Copy-Item 'certs\*' '.\' -Force; Write-Host '[x] Certificate generated successfully!' -ForegroundColor Green"

:done
echo.
echo =====================================================================
echo   [SUCCESS] Native TLS Certificates Generated (Zero Python)!
echo   -------------------------------------------------------------------
echo   Certificate:  certs\cert.pem
echo   Private Key:  certs\key.pem
echo   Android P12:  certs\cert.p12 (Password: 1234)
echo =====================================================================
echo.
pause
