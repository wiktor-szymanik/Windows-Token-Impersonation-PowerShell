param(
    [Parameter(Mandatory = $true)]
    [int]$TargetPID,

    [string]$Application = "C:\Windows\System32\notepad.exe",

    [string]$CommandLine = $null,

    [string]$CurrentDirectory = "C:\Windows\System32"
)

Write-Host "`n[*] Target PID: $TargetPID" -ForegroundColor Cyan
Write-Host "[*] Application: $Application" -ForegroundColor Cyan
if ($CommandLine) {
    Write-Host "[*] CommandLine: $CommandLine" -ForegroundColor Cyan
}

Write-Host "[*] Loading WinAPI..." -ForegroundColor Yellow

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class TokenSpawn
{
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(UInt32 dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ProcessIdToSessionId(int dwProcessId, out int pSessionId);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool DuplicateTokenEx(
        IntPtr hExistingToken,
        UInt32 dwDesiredAccess,
        IntPtr lpTokenAttributes,
        int ImpersonationLevel,
        int TokenType,
        out IntPtr phNewToken
    );

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool SetTokenInformation(
        IntPtr TokenHandle,
        int TokenInformationClass,
        ref int TokenInformation,
        int TokenInformationLength
    );

    [DllImport("userenv.dll", SetLastError=true)]
    public static extern bool CreateEnvironmentBlock(
        out IntPtr lpEnvironment,
        IntPtr hToken,
        bool bInherit
    );

    [DllImport("userenv.dll", SetLastError=true)]
    public static extern bool DestroyEnvironmentBlock(
        IntPtr lpEnvironment
    );

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessAsUserW(
        IntPtr hToken,
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        UInt32 dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation
    );

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO
    {
        public UInt32 cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public UInt32 dwX;
        public UInt32 dwY;
        public UInt32 dwXSize;
        public UInt32 dwYSize;
        public UInt32 dwXCountChars;
        public UInt32 dwYCountChars;
        public UInt32 dwFillAttribute;
        public UInt32 dwFlags;
        public UInt16 wShowWindow;
        public UInt16 cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public IntPtr hProcess;
        public IntPtr hThread;
        public UInt32 dwProcessId;
        public UInt32 dwThreadId;
    }
}
"@

Write-Host "[+] WinAPI loaded`n" -ForegroundColor Green

function Show-LastError {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "[!] WinAPI Error: $err" -ForegroundColor Red
}

function Exit-OnFailure {
    param(
        [string]$Message
    )
    Write-Host "[!] $Message" -ForegroundColor Red
    Show-LastError
    exit 1
}

$PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
$TOKEN_ASSIGN_PRIMARY              = 0x0001
$TOKEN_DUPLICATE                   = 0x0002
$TOKEN_QUERY                       = 0x0008
$TOKEN_ADJUST_DEFAULT              = 0x0080
$TOKEN_ADJUST_SESSIONID            = 0x0100
$TOKEN_ALL_ACCESS                  = 0xF01FF

$SecurityImpersonation             = 2
$TokenPrimary                      = 1
$TokenSessionId                    = 12

$CREATE_UNICODE_ENVIRONMENT        = 0x00000400
$CREATE_NEW_CONSOLE                = 0x00000010

Write-Host "[*] Opening target process..." -ForegroundColor Yellow
$hProcess = [TokenSpawn]::OpenProcess($PROCESS_QUERY_LIMITED_INFORMATION, $false, $TargetPID)
if ($hProcess -eq [IntPtr]::Zero) {
    Exit-OnFailure "OpenProcess FAILED"
}
Write-Host "[+] Process handle: $hProcess"

$targetSession = 0
if (-not [TokenSpawn]::ProcessIdToSessionId($TargetPID, [ref]$targetSession)) {
    Exit-OnFailure "ProcessIdToSessionId(target) FAILED"
}

$currentSession = 0
if (-not [TokenSpawn]::ProcessIdToSessionId($PID, [ref]$currentSession)) {
    Exit-OnFailure "ProcessIdToSessionId(current) FAILED"
}

Write-Host "[*] Target process session: $targetSession" -ForegroundColor Yellow
Write-Host "[*] Current PowerShell session: $currentSession" -ForegroundColor Yellow

$desiredAccess = $TOKEN_ASSIGN_PRIMARY -bor $TOKEN_DUPLICATE -bor $TOKEN_QUERY -bor $TOKEN_ADJUST_DEFAULT -bor $TOKEN_ADJUST_SESSIONID

Write-Host "[*] Opening target process token..." -ForegroundColor Yellow
$hToken = [IntPtr]::Zero
if (-not [TokenSpawn]::OpenProcessToken($hProcess, $desiredAccess, [ref]$hToken)) {
    [TokenSpawn]::CloseHandle($hProcess) | Out-Null
    Exit-OnFailure "OpenProcessToken FAILED"
}
Write-Host "[+] Target token handle: $hToken"

Write-Host "[*] Duplicating token to primary token..." -ForegroundColor Yellow
$hDupToken = [IntPtr]::Zero
if (-not [TokenSpawn]::DuplicateTokenEx(
    $hToken,
    $TOKEN_ALL_ACCESS,
    [IntPtr]::Zero,
    $SecurityImpersonation,
    $TokenPrimary,
    [ref]$hDupToken
)) {
    [TokenSpawn]::CloseHandle($hToken) | Out-Null
    [TokenSpawn]::CloseHandle($hProcess) | Out-Null
    Exit-OnFailure "DuplicateTokenEx FAILED"
}
Write-Host "[+] Duplicated primary token: $hDupToken"


Write-Host "[*] Setting duplicated token SessionId to: $targetSession" -ForegroundColor Yellow
if (-not [TokenSpawn]::SetTokenInformation(
    $hDupToken,
    $TokenSessionId,
    [ref]$targetSession,
    4
)) {
    [TokenSpawn]::CloseHandle($hDupToken) | Out-Null
    [TokenSpawn]::CloseHandle($hToken) | Out-Null
    [TokenSpawn]::CloseHandle($hProcess) | Out-Null
    Exit-OnFailure "SetTokenInformation(TokenSessionId) FAILED"
}
Write-Host "[+] Token SessionId updated"

Write-Host "[*] Creating environment block..." -ForegroundColor Yellow
$lpEnvironment = [IntPtr]::Zero
if (-not [TokenSpawn]::CreateEnvironmentBlock([ref]$lpEnvironment, $hDupToken, $false)) {
    [TokenSpawn]::CloseHandle($hDupToken) | Out-Null
    [TokenSpawn]::CloseHandle($hToken) | Out-Null
    [TokenSpawn]::CloseHandle($hProcess) | Out-Null
    Exit-OnFailure "CreateEnvironmentBlock FAILED"
}
Write-Host "[+] Environment block created: $lpEnvironment"

$si = New-Object TokenSpawn+STARTUPINFO
$pi = New-Object TokenSpawn+PROCESS_INFORMATION
$si.cb = [Runtime.InteropServices.Marshal]::SizeOf([type]([TokenSpawn+STARTUPINFO]))
$si.lpDesktop = "WinSta0\Default"

Write-Host "[*] Spawning process in target session..." -ForegroundColor Yellow
Write-Host "[*] Desktop: $($si.lpDesktop)" -ForegroundColor Yellow
Write-Host "[*] CurrentDirectory: $CurrentDirectory" -ForegroundColor Yellow

$ok = [TokenSpawn]::CreateProcessAsUserW(
    $hDupToken,
    $Application,
    $CommandLine,
    [IntPtr]::Zero,
    [IntPtr]::Zero,
    $false,
    ($CREATE_NEW_CONSOLE -bor $CREATE_UNICODE_ENVIRONMENT),
    $lpEnvironment,
    $CurrentDirectory,
    [ref]$si,
    [ref]$pi
)

if ($ok) {
    Write-Host "[+] Process created successfully!" -ForegroundColor Green
    Write-Host "[+] New PID: $($pi.dwProcessId)" -ForegroundColor Green
    Write-Host "[+] New TID: $($pi.dwThreadId)" -ForegroundColor Green
    Write-Host "[+] Expected session: $targetSession" -ForegroundColor Green
} else {
    Write-Host "[!] CreateProcessAsUserW FAILED" -ForegroundColor Red
    Show-LastError
}

if ($pi.hThread -and $pi.hThread -ne [IntPtr]::Zero) {
    [TokenSpawn]::CloseHandle($pi.hThread) | Out-Null
}
if ($pi.hProcess -and $pi.hProcess -ne [IntPtr]::Zero) {
    [TokenSpawn]::CloseHandle($pi.hProcess) | Out-Null
}
if ($lpEnvironment -and $lpEnvironment -ne [IntPtr]::Zero) {
    [TokenSpawn]::DestroyEnvironmentBlock($lpEnvironment) | Out-Null
}
if ($hDupToken -and $hDupToken -ne [IntPtr]::Zero) {
    [TokenSpawn]::CloseHandle($hDupToken) | Out-Null
}
if ($hToken -and $hToken -ne [IntPtr]::Zero) {
    [TokenSpawn]::CloseHandle($hToken) | Out-Null
}
if ($hProcess -and $hProcess -ne [IntPtr]::Zero) {
    [TokenSpawn]::CloseHandle($hProcess) | Out-Null
}