@echo off
:: =====================================================================
:: view_logs.bat - View Live JioFiber B2BUA RAM Logs (Zero SSD Writes)
:: Reads directly from in-memory Windows Named Pipe \\.\pipe\jio_b2bua_logs
:: =====================================================================

title JioFiber B2BUA Live RAM Log Viewer
echo =====================================================================
echo Streaming live RAM logs from \\.\pipe\jio_b2bua_logs (0 SSD writes)...
echo (Press Ctrl+C to stop viewing)
echo =====================================================================
echo.

powershell -NoProfile -Command "$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'jio_b2bua_logs', [System.IO.Pipes.PipeAccessRights]::Read, [System.IO.Pipes.PipeOptions]::None, [System.Security.Principal.TokenImpersonationLevel]::None, [System.IO.HandleInheritability]::None); try { $pipe.Connect(3000); $sr = New-Object System.IO.StreamReader($pipe); while (-not $sr.EndOfStream) { Write-Host $sr.ReadLine() } } catch { Write-Host '[!] Could not connect to JioFiber B2BUA log pipe. Is the background task running?' -ForegroundColor Red }"

pause
