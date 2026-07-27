@echo off
REM Double-click this to open the Alpaco trading dashboard in your browser.
REM Uses the full python path so it never hits the Microsoft Store stub.
cd /d "%~dp0"
set PY="%LOCALAPPDATA%\Programs\Python\Python314\python.exe"
echo Starting Alpaco dashboard...
echo A browser tab will open at http://localhost:8501
echo Close this window (or press Ctrl+C) to stop it.
echo.
%PY% -m streamlit run dashboard.py
pause
