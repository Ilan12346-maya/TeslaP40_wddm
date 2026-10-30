@echo off
setlocal enabledelayedexpansion

REM --- UAC Check & Elevation ---
:CheckPrivileges
NET FILE 1>NUL 2>NUL
if '%errorlevel%' == '0' ( goto :GotPrivileges ) else ( goto :RequestPrivileges )

:RequestPrivileges
echo Requesting administrator rights...
set "params=%*"
echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"
"%temp%\getadmin.vbs"
del "%temp%\getadmin.vbs"
exit /B

:GotPrivileges
pushd "%CD%"
CD /D "%~dp0"
REM --- End UAC Check ---

REM -------------------------------------------------------------
REM Sets the WDDM-related registry values for an NVIDIA Tesla P40.
REM Finds the GPU automatically (matches "Tesla P40" specifically in
REM the device name) instead of relying on a hardcoded instance ID,
REM so this works regardless of PCIe slot / instance numbering, but
REM deliberately does NOT match other Tesla cards (M40, P100, etc.) —
REM if you have multiple NVIDIA cards installed, only a P40 match is
REM used.
REM
REM Device detection goes through PowerShell/WMI (Win32_PnPSignedDriver),
REM not by parsing pnputil's text output, because pnputil's field labels
REM ("Instance ID:" / "Instanz-ID:" / etc.) are localized and differ by
REM Windows display language, while WMI property names are not.
REM -------------------------------------------------------------

set "BASE=HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
echo Searching for a registry subkey with a Tesla P40 in DriverDesc...
set "FOUND_KEY="
set "FOUND_DESC="

for /f "tokens=*" %%K in ('reg query "%BASE%"') do (
    set "LINE=%%K"
    for %%S in ("!LINE:%BASE%\=!") do (
        set "SUBKEY=%%~S"
        if "!SUBKEY:~0,3!"=="000" (
            for /f "skip=2 tokens=2,*" %%A in ('reg query "%BASE%\!SUBKEY!" /v DriverDesc 2^>nul') do (
                set "DESC=%%B"
                echo !DESC! | findstr /i "Tesla P40" >nul
                if not errorlevel 1 (
                    set "FOUND_KEY=!SUBKEY!"
                    set "FOUND_DESC=!DESC!"
                    goto :Found
                )
            )
        )
    )
)

:Found
if not defined FOUND_KEY (
    echo ERROR: No Tesla P40 found in the registry. Nothing was changed. Aborting.
    pause
    exit /B 1
)

echo Found: %FOUND_DESC%  ^(subkey %FOUND_KEY%^)
set "KEY=%BASE%\%FOUND_KEY%"
echo.
echo Using registry path:
echo   %KEY%
echo.

REM -------------------------------------------------------------
REM Set the registry values
REM -------------------------------------------------------------

echo Setting AllowWddmOnTesla to 1...
reg add "%KEY%" /v AllowWddmOnTesla /t REG_DWORD /d 1 /f >nul 2>&1
if %errorlevel% neq 0 (echo FAILED: AllowWddmOnTesla) else (echo OK: AllowWddmOnTesla = 1)

echo Setting AdapterType to 1...
reg add "%KEY%" /v AdapterType /t REG_DWORD /d 1 /f >nul 2>&1
if %errorlevel% neq 0 (echo FAILED: AdapterType) else (echo OK: AdapterType = 1)

echo Setting FeatureScore to D1 (hex)...
reg add "%KEY%" /v FeatureScore /t REG_BINARY /d D1 /f >nul 2>&1
if %errorlevel% neq 0 (echo FAILED: FeatureScore) else (echo OK: FeatureScore = D1)

echo Setting GridLicensedFeatures to 7...
reg add "%KEY%" /v GridLicensedFeatures /t REG_DWORD /d 7 /f >nul 2>&1
if %errorlevel% neq 0 (echo FAILED: GridLicensedFeatures) else (echo OK: GridLicensedFeatures = 7)

echo Setting EnableMsHybrid to 1...
reg add "%KEY%" /v EnableMsHybrid /t REG_DWORD /d 1 /f >nul 2>&1
if %errorlevel% neq 0 (echo FAILED: EnableMsHybrid) else (echo OK: EnableMsHybrid = 1)

echo.
echo --- Verifying values currently set ---
reg query "%KEY%" /v AllowWddmOnTesla
reg query "%KEY%" /v AdapterType
reg query "%KEY%" /v FeatureScore
reg query "%KEY%" /v GridLicensedFeatures
reg query "%KEY%" /v EnableMsHybrid
echo.

REM -------------------------------------------------------------
REM Find the matching PnP device instance dynamically via WMI
REM (locale-independent), NOT a hardcoded ID and NOT by parsing
REM pnputil's localized text output.
REM -------------------------------------------------------------

echo Searching for the matching PnP device instance via WMI...
set "DEVID="
for /f "usebackq delims=" %%D in (`
    powershell -NoProfile -Command ^
    "(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -like '*Tesla P40*' -and $_.Manufacturer -like '*NVIDIA*' } | Select-Object -First 1 -ExpandProperty DeviceID)"
`) do set "DEVID=%%D"

if not defined DEVID (
    echo ERROR: Could not automatically find the PnP instance ID for the Tesla P40 via WMI.
    echo Registry values were already set above, so WDDM should take effect on the
    echo next full reboot even without the device reset below.
    echo.
    echo To reset the device manually without rebooting, run:
    echo   pnputil /enum-devices /connected
    echo find your card's instance ID line ^(look for VEN_10DE and DEV_1B38, or
    echo "Tesla P40" in the description, whatever that field is labeled in your
    echo Windows language^), then:
    echo   pnputil /disable-device "<that ID>"
    echo   pnputil /enable-device "<that ID>"
    pause
    exit /B 1
)

echo Found PnP instance: %DEVID%
echo.

echo Disabling Tesla GPU...
pnputil /disable-device "%DEVID%"
if %errorlevel% neq 0 (
    echo FAILED to disable device ^(errorlevel %errorlevel%^). Check the instance ID above.
    pause
    exit /B 1
)

timeout /t 2 >nul

echo Enabling Tesla GPU...
pnputil /enable-device "%DEVID%"
if %errorlevel% neq 0 (
    echo FAILED to enable device ^(errorlevel %errorlevel%^).
    pause
    exit /B 1
)

echo.
echo Done. Registry values set and GPU reset. Run nvidia-smi to verify WDDM mode.
echo If it still shows TCC, a full reboot may be required.
pause
