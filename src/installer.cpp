#include <windows.h>
#include <shellapi.h>
#include <iostream>
#include <fstream>
#include <string>

bool is_admin() {
    BOOL isAdmin = FALSE;
    PSID adminGroup = NULL;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
        DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &adminGroup)) {
        CheckTokenMembership(NULL, adminGroup, &isAdmin);
        FreeSid(adminGroup);
    }
    return isAdmin == TRUE;
}

void run_cmd(const std::string& cmd) {
    system(cmd.c_str());
}

int main() {
    SetConsoleTitleA("JioFiber SIP B2BUA Setup");
    std::cout << "=====================================================================\n";
    std::cout << "   JioFiber SIP B2BUA Windows Setup & Installer\n";
    std::cout << "=====================================================================\n\n";

    if (!is_admin()) {
        std::cout << "[!] Administrator privileges required. Restarting with Admin permissions...\n";
        char szPath[MAX_PATH];
        GetModuleFileNameA(NULL, szPath, MAX_PATH);
        SHELLEXECUTEINFOA sei = { sizeof(sei) };
        sei.lpVerb = "runas";
        sei.lpFile = szPath;
        sei.hwnd = NULL;
        sei.nShow = SW_NORMAL;
        if (!ShellExecuteExA(&sei)) {
            std::cout << "[!] Failed to acquire Administrator privileges.\n";
            system("pause");
            return 1;
        }
        return 0;
    }

    char program_files[MAX_PATH];
    GetEnvironmentVariableA("ProgramFiles", program_files, MAX_PATH);
    std::string target_dir = std::string(program_files) + "\\JioFiberB2BUA";

    std::cout << "[*] Installation Directory: " << target_dir << "\n";
    CreateDirectoryA(target_dir.c_str(), NULL);

    char current_dir[MAX_PATH];
    GetCurrentDirectoryA(MAX_PATH, current_dir);

    std::string src_exe = std::string(current_dir) + "\\bin\\windows-x64\\b2bua_msvc.exe";
    if (!GetFileAttributesA(src_exe.c_str())) {
        src_exe = std::string(current_dir) + "\\b2bua_msvc.exe";
    }

    std::string dst_exe = target_dir + "\\b2bua_msvc.exe";

    std::cout << "Select Installation Mode:\n";
    std::cout << "  [1] Service Mode (Auto-starts silently in background on Windows boot) [DEFAULT]\n";
    std::cout << "  [2] Non-Service / Interactive Console Mode (Runs in visible window with live logs)\n\n";
    std::cout << "Enter choice (1 or 2) [1]: ";

    std::string choice;
    std::getline(std::cin, choice);

    bool is_service_mode = (choice != "2");

    std::cout << "\n[*] Step 1/3: Copying application binaries & log viewer...\n";
    if (GetFileAttributesA(src_exe.c_str()) != INVALID_FILE_ATTRIBUTES) {
        CopyFileA(src_exe.c_str(), dst_exe.c_str(), FALSE);
    } else {
        std::cout << "[*] Downloading latest b2bua_msvc.exe from GitHub...\n";
        std::string dl_cmd = "powershell -Command \"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/b2bua_msvc.exe' -OutFile '" + dst_exe + "'\"";
        run_cmd(dl_cmd);
    }

    // Write view_logs.bat to target directory
    std::string view_logs_path = target_dir + "\\view_logs.bat";
    std::ofstream vl_file(view_logs_path);
    if (vl_file.is_open()) {
        vl_file << "@echo off\n";
        vl_file << "title JioFiber B2BUA Live Log Viewer\n";
        vl_file << "color 0B\n";
        vl_file << "echo =====================================================================\n";
        vl_file << "echo    JioFiber B2BUA Live Log Stream (RAM Ring-Buffer / Named Pipe)\n";
        vl_file << "echo =====================================================================\n";
        vl_file << "echo.\n";
        vl_file << "powershell -NoProfile -ExecutionPolicy Bypass -Command \"$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'jio_b2bua_logs', [System.IO.Pipes.PipeDirection]::In); Write-Host '[*] Connecting to log pipe...' -ForegroundColor Yellow; try { $pipe.Connect(5000); Write-Host '[*] Connected! Streaming live logs (Press Ctrl+C to exit)...' -ForegroundColor Green; $reader = New-Object System.IO.StreamReader($pipe); while ($null -ne ($line = $reader.ReadLine())) { Write-Host $line } } catch { Write-Host '[!] Could not connect to B2BUA log pipe. Is b2bua_msvc.exe running?' -ForegroundColor Red }\"\n";
        vl_file << "pause\n";
        vl_file.close();
    }

    // Create Desktop Shortcut for Log Viewer
    std::string shortcut_cmd = "powershell -Command \"$s = (New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop') + '\\JioFiber B2BUA Log Viewer.lnk'); $s.TargetPath = '" + view_logs_path + "'; $s.WorkingDirectory = '" + target_dir + "'; $s.Save()\"";
    run_cmd(shortcut_cmd);

    std::cout << "[*] Step 2/3: Opening Windows Firewall ports...\n";
    run_cmd("netsh advfirewall firewall delete rule name=\"JioFiber B2BUA SIP UDP\" >nul 2>&1");
    run_cmd("netsh advfirewall firewall add rule name=\"JioFiber B2BUA SIP UDP\" dir=in action=allow protocol=UDP localport=5061");
    run_cmd("netsh advfirewall firewall delete rule name=\"JioFiber B2BUA SIP TLS\" >nul 2>&1");
    run_cmd("netsh advfirewall firewall add rule name=\"JioFiber B2BUA SIP TLS\" dir=in action=allow protocol=TCP localport=5062");
    run_cmd("netsh advfirewall firewall delete rule name=\"JioFiber B2BUA RTP Media UDP\" >nul 2>&1");
    run_cmd("netsh advfirewall firewall add rule name=\"JioFiber B2BUA RTP Media UDP\" dir=in action=allow protocol=UDP localport=52000-52200");

    if (is_service_mode) {
        std::cout << "[*] Step 3/3: Installing & starting Windows Service...\n";
        run_cmd("taskkill /F /IM b2bua_msvc.exe >nul 2>&1");
        run_cmd("sc stop JioFiberB2BUA >nul 2>&1");
        run_cmd("sc delete JioFiberB2BUA >nul 2>&1");

        std::string sc_cmd = "sc create JioFiberB2BUA binPath= \"\\\"" + dst_exe + "\\\"\" start= auto DisplayName= \"JioFiber SIP B2BUA Service\"";
        run_cmd(sc_cmd);
        run_cmd("sc description JioFiberB2BUA \"Lightweight native SIP B2BUA proxy for JioFiber VoIP\"");
        run_cmd("sc start JioFiberB2BUA");

        std::cout << "\n=====================================================================\n";
        std::cout << "   [SUCCESS] JioFiber B2BUA Installed & Running in SERVICE MODE!\n";
        std::cout << "   -------------------------------------------------------------------\n";
        std::cout << "   Installed Path:  " << dst_exe << "\n";
        std::cout << "   Mode:            Windows Service (Starts on Boot)\n";
        std::cout << "   SIP UDP Port:    5061\n";
        std::cout << "   SIP TLS Port:    5062\n";
        std::cout << "=====================================================================\n\n";
    } else {
        std::cout << "[*] Step 3/3: Configuring Non-Service / Interactive Console Mode...\n";
        run_cmd("sc stop JioFiberB2BUA >nul 2>&1");
        run_cmd("sc delete JioFiberB2BUA >nul 2>&1");
        run_cmd("taskkill /F /IM b2bua_msvc.exe >nul 2>&1");

        std::cout << "\n=====================================================================\n";
        std::cout << "   [SUCCESS] JioFiber B2BUA Configured in INTERACTIVE CONSOLE MODE!\n";
        std::cout << "   -------------------------------------------------------------------\n";
        std::cout << "   Installed Path:  " << dst_exe << "\n";
        std::cout << "   Mode:            Non-Service / Interactive Window\n";
        std::cout << "   SIP UDP Port:    5061\n";
        std::cout << "   SIP TLS Port:    5062\n";
        std::cout << "=====================================================================\n\n";
        std::cout << "[*] Launching JioFiber B2BUA interactively now...\n\n";
        std::string launch_cmd = "start \"JioFiber B2BUA Interactive\" \"" + dst_exe + "\"";
        run_cmd(launch_cmd);
    }
    system("pause");
    return 0;
}
