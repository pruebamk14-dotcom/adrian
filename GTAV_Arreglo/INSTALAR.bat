@echo off
title Arreglo texturas GTA V
echo ============================================
echo   ARREGLO DE TEXTURAS GTA V (Resource Adjuster)
echo ============================================
echo.
set "GTA=C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V"
if exist "%GTA%\GTA5.exe" goto found
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul ^| find "SteamPath"') do set "STEAM=%%B"
if defined STEAM (
  set "STEAM=%STEAM:/=\%"
  if exist "%STEAM%\steamapps\common\Grand Theft Auto V\GTA5.exe" set "GTA=%STEAM%\steamapps\common\Grand Theft Auto V"
)
if exist "%GTA%\GTA5.exe" goto found
echo No encontre GTA V solo.
echo En Steam: clic derecho en GTA V - Administrar - Ver archivos locales,
echo copia la ruta de la barra de arriba y pegala aqui.
set /p GTA=Ruta: 
set "GTA=%GTA:"=%"
if not exist "%GTA%\GTA5.exe" (
  echo No encuentro GTA5.exe en esa ruta. Intenta de nuevo.
  pause
  exit /b
)
:found
echo Encontre GTA V en: %GTA%
echo.
echo Cuanta memoria de video (VRAM) tiene tu tarjeta?
echo   1 = 4 GB o menos
echo   2 = 6 GB
echo   3 = 8 GB
echo   4 = 10 o 12 GB
echo   5 = 16 GB o mas
echo (No sabes? Presiona la tecla Windows, escribe "dxdiag", pestana Pantalla)
choice /c 12345 /n /m "Elige 1-5: "
set VRAM=800
if errorlevel 5 set VRAM=4500
if errorlevel 4 if not errorlevel 5 set VRAM=3000
if errorlevel 3 if not errorlevel 4 set VRAM=1900
if errorlevel 2 if not errorlevel 3 set VRAM=800
if errorlevel 1 if not errorlevel 2 set VRAM=400
echo.
echo Cuanta RAM tiene tu PC?
echo   1 = 16 GB o menos
echo   2 = 32 GB o mas
choice /c 12 /n /m "Elige 1-2: "
set EXP=0
if errorlevel 2 set EXP=1
copy /y "%~dp0archivos\GTAV.ResourceAdjuster.asi" "%GTA%\" >nul
(
echo [Config]
echo showLog=1
echo enableExperimentalMode=%EXP%
echo.
echo [Settings]
echo additionalGPUMemory=%VRAM%
) > "%GTA%\ResourceAdjuster.ini"
echo.
if exist "%GTA%\dinput8.dll" (echo ASI Loader: OK) else (echo AVISO: no veo dinput8.dll. Instala "ASI Loader" desde OpenIV - Tools - ASI Manager.)
echo.
echo LISTO. VRAM extra: %VRAM% MiB - Modo experimental: %EXP%
echo Ya puedes abrir GTA V (version Legacy).
pause
