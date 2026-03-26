# Windows Token Impersonation (PowerShell)

This repository demonstrates Windows access token duplication and two practical ways of using it:

- In-place impersonation (thread-level)
- Creating a new process with a duplicated token (process-level)

## Overview

Windows allows a process to act as another user by duplicating and applying access tokens.  
This project shows how identity can be applied at the thread level without changing the process itself.

## Scripts

### TokenImpersonation.ps1

Performs in-place impersonation using a duplicated token.

- Uses `DuplicateTokenEx`
- Applies token via `ImpersonateLoggedOnUser`
- Affects current thread context

### TokenImpersonation-Spawn.ps1

Creates a new process using a duplicated token.

- Uses `CreateProcessWithTokenW`
- Starts a new process (example: cmd.exe) as target user
- Full process-level identity

## Test

1. Identify target process (example: domain user or service account)
2. Duplicate its token via one of the scripts


## Disclaimer

This project is intended for educational and authorized security testing only.  
Do not use in environments without proper permission.