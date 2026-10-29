@echo off
setlocal enabledelayedexpansion

:: =============================================================
:: Elevate to Administrator
:: =============================================================
NET FILE 1>NUL 2>NUL
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /B
)

pushd "%CD%"
CD /D "%~dp0"

echo ============================================================
echo   Tesla P40 WDDM Registry Switch & GPU Restart
echo ============================================================
echo.

set "BASE=HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
set "TARGET_DESC=NVIDIA Tesla P40"
set "FOUND_KEY="

echo Searching for device subkey with DriverDesc="%TARGET_DESC%"...

for /f "tokens=*" %%K in ('reg query "%BASE%"') do (
    set "LINE=%%K"
    for %%S in ("!LINE:%BASE%\=!") do (
        set "SUBKEY=%%~S"
        if "!SUBKEY:~0,3!"=="000" (
            for /f "skip=2 tokens=2,*" %%A in ('reg query "%BASE%\!SUBKEY!" /v DriverDesc 2^>nul') do (
                if "%%B"=="%TARGET_DESC%" (
                    set "FOUND_KEY=!SUBKEY!"
                    goto :Found
                )
            )
        )
    )
)

:Found
if defined FOUND_KEY (
    echo [OK] Found Tesla P40 at: %BASE%\%FOUND_KEY%
    set "KEY=%BASE%\%FOUND_KEY%"
) else (
    echo [!] Warning: Tesla P40 not found by description. Defaulting to 0000...
    set "KEY=%BASE%\0000"
)

echo.
echo Writing WDDM parameters into Registry...

reg add "%KEY%" /v AdapterType /t REG_DWORD /d 1 /f >nul
if errorlevel 0 (echo   [+] AdapterType = 1) else (echo   [-] Failed to set AdapterType)

reg add "%KEY%" /v EnableMsHybrid /t REG_DWORD /d 1 /f >nul
if errorlevel 0 (echo   [+] EnableMsHybrid = 1) else (echo   [-] Failed to set EnableMsHybrid)

reg add "%KEY%" /v GridLicensedFeatures /t REG_DWORD /d 7 /f >nul
if errorlevel 0 (echo   [+] GridLicensedFeatures = 7) else (echo   [-] Failed to set GridLicensedFeatures)

reg add "%KEY%" /v AllowWddmOnTesla /t REG_DWORD /d 1 /f >nul
if errorlevel 0 (echo   [+] AllowWddmOnTesla = 1) else (echo   [-] Failed to set AllowWddmOnTesla)

echo.
echo Restarting Tesla P40 device via pnputil...
pnputil /restart-device "PCI\VEN_10DE&DEV_1B38*" >nul 2>&1
if errorlevel 1 (
    echo [!] pnputil restart failed, attempting disable/enable cycle...
    pnputil /disable-device "PCI\VEN_10DE&DEV_1B38*" >nul 2>&1
    timeout /t 2 >nul
    pnputil /enable-device "PCI\VEN_10DE&DEV_1B38*" >nul 2>&1
)

echo [OK] GPU reloaded. Run 'nvidia-smi' to verify WDDM mode!
pause
