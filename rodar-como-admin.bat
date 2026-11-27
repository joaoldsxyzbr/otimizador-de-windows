@echo off
rem Duplo clique = pede elevacao (UAC). Aceite e o app abre liberado
rem (modo Administrador). Se recusar o UAC, nada e aberto.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Pedindo permissao de administrador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0otimizadorpc.ps1"
pause
