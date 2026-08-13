@echo off
title JioFiber B2BUA Live Log Viewer
color 0B

echo =====================================================================
echo    JioFiber B2BUA Live Log Stream (RAM Ring-Buffer / Named Pipe)
echo =====================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'jio_b2bua_logs', [System.IO.Pipes.PipeDirection]::In); Write-Host '[*] Connecting to log pipe...' -ForegroundColor Yellow; try { $pipe.Connect(5000); Write-Host '[*] Connected! Streaming live logs (Press Ctrl+C to exit)...' -ForegroundColor Green; $reader = New-Object System.IO.StreamReader($pipe); while ($null -ne ($line = $reader.ReadLine())) { Write-Host $line } } catch { Write-Host '[!] Could not connect to B2BUA log pipe. Is b2bua_msvc.exe running?' -ForegroundColor Red }"

echo.
pause
