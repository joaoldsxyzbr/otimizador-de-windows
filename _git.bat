@echo off
set "PATH=%PATH%;C:\Program Files\Git\cmd"
cd /d "%~dp0"
git init
git add -A
git status --short
