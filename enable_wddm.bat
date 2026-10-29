@echo off
setlocal enabledelayedexpansion

REM --- UAC Check & Elevation ---
:CheckPrivileges
NET FILE 1>NUL 2>NUL
if '%errorlevel%' == '0' ( goto :GotPrivileges ) else ( goto :RequestPrivileges )

:RequestPrivileges
echo Fordere Administratorrechte an...
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
REM Zweck:   Registry-Einträge für Tesla P40 in WDDM-Modus setzen,
REM          automatisches Finden des passenden Unterschlüssels
REM -------------------------------------------------------------

REM Basis-Pfad (ohne Unterschlüssel)
set "BASE=HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
set "TARGET_DESC=NVIDIA Tesla P40"
REM set "TARGET_DESC=NVIDIA Quadro P6000"
echo Suche nach dem Unterschluessel mit DriverDesc="%TARGET_DESC%"...
set "FOUND_KEY="

REM Alle Unterschlüssel des Class-Keys auflisten
for /f "tokens=*" %%K in ('reg query "%BASE%"') do (
    set "LINE=%%K"
    REM Extrahiere den reinen Unterschlüssel-Namen (z.B. 0000, 0001, ...)
    for %%S in ("!LINE:%BASE%\=!") do (
        set "SUBKEY=%%~S"
        REM Nur numerische Keys 000x prüfen
        if "!SUBKEY:~0,3!"=="000" (
            REM DriverDesc-Wert auslesen
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
    echo Gefunden: Unterschluessel %FOUND_KEY%
    set "KEY=%BASE%\%FOUND_KEY%"
) else (
    echo WARNUNG: Tesla P40 nicht gefunden. Nutze Default-Unterschluessel 0000.
    set "KEY=%BASE%\0014"
)

echo.
echo Verwende Registry-Pfad:
echo   %KEY%
echo.

REM -------------------------------------------------------------
REM Jetzt die gewünschten Werte setzen
REM -------------------------------------------------------------

echo Setze AllowWddmOnTesla auf 1...
reg add "%KEY%" /v AllowWddmOnTesla /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 (
    echo FEHLER: AllowWddmOnTesla konnte nicht gesetzt werden.
) else (
    echo OK: AllowWddmOnTesla = 1
)

echo Setze AdapterType auf 1...
reg add "%KEY%" /v AdapterType /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 (
    echo FEHLER: AdapterType konnte nicht gesetzt werden.
) else (
    echo OK: AdapterType = 1
)

echo Setze FeatureScore auf D1 (hex)...
reg add "%KEY%" /v FeatureScore /t REG_BINARY /d D1 /f >nul 2>&1
if errorlevel 1 (
    echo FEHLER: FeatureScore konnte nicht gesetzt werden.
) else (
    echo OK: FeatureScore = D1
)

echo Setze GridLicensedFeatures auf 7...
reg add "%KEY%" /v GridLicensedFeatures /t REG_DWORD /d 7 /f >nul 2>&1
if errorlevel 1 (
    echo FEHLER: GridLicensedFeatures konnte nicht gesetzt werden.
) else (
    echo OK: GridLicensedFeatures = 7
)

echo Setze EnableMsHybrid auf 1...
reg add "%KEY%" /v EnableMsHybrid /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 (
    echo FEHLER: EnableMsHybrid konnte nicht gesetzt werden.
) else (
    echo OK: EnableMsHybrid = 1
)

echo.
echo Alle Registry-Werte erfolgreich aktualisiert fuer:
echo   %KEY%

echo.
echo Deaktiviere Tesla P40...
pnputil /disable-device "PCI\VEN_10DE&DEV_1B38&SUBSYS_11D910DE&REV_A1\4&7D659FE&0&0009"
timeout /t 2 >nul
echo Aktiviere Tesla P40...
pnputil /enable-device "PCI\VEN_10DE&DEV_1B38&SUBSYS_11D910DE&REV_A1\4&7D659FE&0&0009"

if errorlevel 0 (
    echo GPU erfolgreich aus- und eingeschaltet.
) else (
    echo FEHLER beim Reset der GPU.
)

pause

