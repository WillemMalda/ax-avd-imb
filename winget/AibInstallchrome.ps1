<#
.SYNOPSIS
    Azure Image Builder script to install Google Chrome machine-wide using Winget.
.DESCRIPTION
    This script:
    - Assumes Winget is already installed and initialized.
    - Dynamically locates Winget to ensure execution.
    - Installs Postman with machine scope (system-wide).
    - Handles fallback if machine scope fails.
    - Creates Start Menu shortcut for all users.
.AUTHOR
    Luuk Ros
.VERSION
    3.0
.LAST UPDATED
    23-09-2025
#>
#################################################################
#                 START AIB IMAGE BUILDER PHASE                 #
#################################################################
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "*** AIB CUSTOMIZER PHASE: Installing Google Chrome Machine-Wide ***"

# Ensure running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "*** AIB CUSTOMIZER PHASE WARNING: Not running as Administrator. Machine-wide installation may fail. ***"
}

# Locate winget dynamically
$wingetPath = Get-ChildItem -Path "$env:SystemDrive\Program Files\WindowsApps" -Recurse -Filter "winget.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -First 1

# If winget is still not found, fail gracefully
if (-not $wingetPath) {
    Write-Host "*** AIB CUSTOMIZER PHASE ERROR: Winget not found in WindowsApps. Exiting... ***"
    exit 1
}
Write-Host "*** Using Winget from: $wingetPath ***"

# Define application details
$wingetAppId = "Google.Chrome"
$wingetAppName = "Google Chrome"

# Install Postman using Winget with machine scope
Write-Host "*** AIB CUSTOMIZER PHASE *** Installing $wingetAppName ($wingetAppId) machine-wide using Winget ***"

try {
    # Primary attempt: Install with --scope machine
    Write-Host "*** Attempting machine-wide installation with scope parameter ***"
    
    $installArgs = @(
        "install",
        "--id", $wingetAppId,
    #    "--scope", "machine", 
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--disable-interactivity",
        "--force"
    )
    
    # Log the full command for debugging
    Write-Host "*** Executing: $wingetPath $($installArgs -join ' ') ***"
    
    $process = Start-Process -FilePath $wingetPath `
                            -ArgumentList $installArgs `
                            -Wait `
                            -NoNewWindow `
                            -PassThru `
                            -RedirectStandardOutput "$env:TEMP\winget_output.txt" `
                            -RedirectStandardError "$env:TEMP\winget_error.txt"
    
    # Check output
    if (Test-Path "$env:TEMP\winget_output.txt") {
        $output = Get-Content "$env:TEMP\winget_output.txt" -Raw
        Write-Host "*** Winget Output: $output ***"
    }
    
    if (Test-Path "$env:TEMP\winget_error.txt") {
        $errorOutput = Get-Content "$env:TEMP\winget_error.txt" -Raw
        if ($errorOutput) {
            Write-Host "*** Winget Error Output: $errorOutput ***"
        }
    }
    
    if ($process.ExitCode -eq 0) {
        Write-Host "*** AIB CUSTOMIZER PHASE *** Successfully installed $wingetAppName machine-wide ***"
    } else {
        # Fallback: Try with override parameter to force machine installation
        Write-Host "*** Initial machine-wide installation returned exit code $($process.ExitCode). Trying with override parameter... ***"
        
        $overrideArgs = @(
            "install",
            "--id", $wingetAppId,
            "--scope", "machine",
            "--override", "/ALLUSERS=1 /VERYSILENT",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--force"
        )
        
        $process = Start-Process -FilePath $wingetPath `
                                -ArgumentList $overrideArgs `
                                -Wait `
                                -NoNewWindow `
                                -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Host "*** AIB CUSTOMIZER PHASE ERROR *** Machine-wide installation failed with exit code $($process.ExitCode) ***"
            
            # Final fallback: Manual installation approach
            Write-Host "*** Attempting manual download and installation approach ***"
            
            # Download Postman installer
            $installerUrl = "https://dl.pstmn.io/download/latest/win64"
            $installerPath = "$env:TEMP\PostmanInstaller.exe"
            
            try {
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
                
                # Run installer with machine-wide parameters
                Start-Process -FilePath $installerPath `
                             -ArgumentList "/S", "/ALLUSERS=1" `
                             -Wait `
                             -NoNewWindow
                
                Write-Host "*** Manual installation completed ***"
            } catch {
                Write-Host "*** AIB CUSTOMIZER PHASE ERROR *** Manual installation also failed: $($_.Exception.Message) ***"
                exit 1
            }
        } else {
            Write-Host "*** AIB CUSTOMIZER PHASE *** Successfully installed $wingetAppName with override parameters ***"
        }
    }
} catch {
    Write-Host "*** AIB CUSTOMIZER PHASE ERROR *** Failed to install $wingetAppName [$($_.Exception.Message)] ***"
    exit 1
}

# Wait for installation to complete
Write-Host "*** Waiting for installation to finalize... ***"
Start-Sleep -Seconds 15

# Search for Postman installation in machine-wide locations first
Write-Host "*** AIB CUSTOMIZER PHASE: Searching for Postman installation path (machine-wide locations) ***"

$machineWidePaths = @(
    "$env:ProgramFiles\Postman\Postman.exe",
    "${env:ProgramFiles(x86)}\Postman\Postman.exe",
    "$env:ProgramFiles\Postman\app\Postman.exe",
    "${env:ProgramFiles(x86)}\Postman\app\Postman.exe"
)

$postmanExePath = $null
foreach ($path in $machineWidePaths) {
    if (Test-Path $path) {
        $postmanExePath = $path
        Write-Host "*** AIB CUSTOMIZER PHASE: Found Postman at machine-wide location: $path ***"
        break
    }
}

# If not found in machine-wide locations, check user locations (shouldn't happen with machine scope)
if (-not $postmanExePath) {
    Write-Host "*** AIB CUSTOMIZER PHASE: Postman not found in Program Files. Checking user locations... ***"
    
    $userPaths = @(
        "$env:LOCALAPPDATA\Postman\Postman.exe",
        "$env:APPDATA\Postman\Postman.exe",
        "C:\Users\Default\AppData\Local\Postman\Postman.exe"
    )
    
    foreach ($path in $userPaths) {
        if (Test-Path $path) {
            $postmanExePath = $path
            Write-Host "*** AIB CUSTOMIZER PHASE WARNING: Found Postman in user location: $path ***"
            Write-Host "*** This indicates machine-wide installation may have failed ***"
            
            # Move to Program Files for machine-wide access
            $targetDir = "$env:ProgramFiles\Postman"
            if (-not (Test-Path $targetDir)) {
                try {
                    Write-Host "*** Moving Postman to Program Files for machine-wide access ***"
                    $sourceDir = Split-Path $postmanExePath -Parent
                    
                    # Create target directory
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    
                    # Copy all files
                    Copy-Item -Path "$sourceDir\*" -Destination $targetDir -Recurse -Force
                    
                    # Update path
                    $postmanExePath = Join-Path $targetDir "Postman.exe"
                    
                    # Remove original user installation
                    Remove-Item -Path $sourceDir -Recurse -Force -ErrorAction SilentlyContinue
                    
                    Write-Host "*** Successfully moved Postman to machine-wide location ***"
                } catch {
                    Write-Host "*** AIB CUSTOMIZER PHASE ERROR: Failed to move to Program Files: $($_.Exception.Message) ***"
                }
            }
            break
        }
    }
}

# Create Start Menu shortcut for all users
if ($postmanExePath -and (Test-Path $postmanExePath)) {
    Write-Host "*** AIB CUSTOMIZER PHASE: Creating Start Menu Shortcut for all users ***"
    
    $shortcutPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Postman.lnk"
    $workingDirectory = Split-Path $postmanExePath -Parent
    
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = $postmanExePath
        $Shortcut.WorkingDirectory = $workingDirectory
        $Shortcut.IconLocation = "$postmanExePath,0"
        $Shortcut.Description = "Postman API Platform"
        $Shortcut.Save()
        
        # Release COM object
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell) | Out-Null
        
        Write-Host "*** AIB CUSTOMIZER PHASE: Successfully created Start Menu shortcut for all users ***"
        
        # Set appropriate permissions on the shortcut
        $acl = Get-Acl $shortcutPath
        $permission = "BUILTIN\Users","ReadAndExecute","Allow"
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
        $acl.SetAccessRule($accessRule)
        Set-Acl $shortcutPath $acl
        
        Write-Host "*** Set permissions on shortcut for all users ***"
    } catch {
        Write-Host "*** AIB CUSTOMIZER PHASE WARNING: Failed to create/configure shortcut [$($_.Exception.Message)] ***"
    }
    
    # Add to PATH for all users (optional but recommended)
    try {
        $postmanDir = Split-Path $postmanExePath -Parent
        $currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
        
        if ($currentPath -notlike "*$postmanDir*") {
            Write-Host "*** Adding Postman to system PATH ***"
            $newPath = "$currentPath;$postmanDir"
            [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::Machine)
            Write-Host "*** Successfully added Postman to system PATH ***"
        } else {
            Write-Host "*** Postman already in system PATH ***"
        }
    } catch {
        Write-Host "*** AIB CUSTOMIZER PHASE WARNING: Failed to add to PATH [$($_.Exception.Message)] ***"
    }
} else {
    Write-Host "*** AIB CUSTOMIZER PHASE ERROR: Postman executable not found after installation ***"
    
    # Last resort: perform a system-wide search
    Write-Host "*** Performing system-wide search for Postman.exe... ***"
    $searchResult = Get-ChildItem -Path "C:\" -Recurse -Filter "Postman.exe" -ErrorAction SilentlyContinue | 
                   Where-Object { $_.FullName -notlike "*\Temp\*" -and $_.FullName -notlike "*\Downloads\*" } | 
                   Select-Object -First 1
    
    if ($searchResult) {
        Write-Host "*** Found Postman at: $($searchResult.FullName) ***"
    } else {
        Write-Host "*** AIB CUSTOMIZER PHASE ERROR: Postman installation could not be verified ***"
        exit 1
    }
}

# Verify installation via winget
Write-Host "*** AIB CUSTOMIZER PHASE: Verifying installation via Winget ***"
$verifyProcess = Start-Process -FilePath $wingetPath `
    -ArgumentList "list", "--id", $wingetAppId, "--scope", "machine" `
    -Wait -NoNewWindow -PassThru `
    -RedirectStandardOutput "$env:TEMP\winget_verify.txt"

if (Test-Path "$env:TEMP\winget_verify.txt") {
    $verifyOutput = Get-Content "$env:TEMP\winget_verify.txt" -Raw
    Write-Host "*** Verification Output: $verifyOutput ***"
}

# Clean up temporary files
Remove-Item "$env:TEMP\winget_*.txt" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\PostmanInstaller.exe" -Force -ErrorAction SilentlyContinue

# Finalize script execution
$stopwatch.Stop()
$elapsedTime = $stopwatch.Elapsed
Write-Host "*** AIB CUSTOMIZER PHASE: Machine-wide installation of $wingetAppName completed in $elapsedTime ***"

# Final status check
if ($postmanExePath -and (Test-Path $postmanExePath)) {
    Write-Host "*** SUCCESS: Postman installed at: $postmanExePath ***"
    exit 0
} else {
    Write-Host "*** FAILURE: Postman installation could not be verified ***"
    exit 1
}

#################################################################
#                         END OF SCRIPT                         #
#################################################################
