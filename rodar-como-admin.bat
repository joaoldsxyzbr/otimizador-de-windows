@echo off
rem ============================================================
rem  otimizadorpc - lanca o app pedindo elevacao de administrador
rem  o script ps1 ja se auto-eleva; este bat e so um atalho
rem  com duplo clique para o joao nao precisar digitar nada
rem ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0otimizadorpc.ps1"
