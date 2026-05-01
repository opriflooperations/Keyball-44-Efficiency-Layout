# Build and Download Firmware Script
# This script builds the ZMK firmware and downloads it to the Keyball44

param(
    [string]$CommitMessage = ""
)

# Configuration - Update these paths as needed
$RepoPath = "C:\Code\KeyBall44 Keyboard Layout Setup\Keyball44 Backend Code\Keyball-44-Efficiency-Layout"
$BuildVersionsPath = "$env:USERPROFILE\Downloads"

# Paths
$GhExePath = "C:\Program Files\GitHub CLI\gh.exe"

# Show commit message popup if no message provided
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $CommitMessage = [Microsoft.VisualBasic.Interaction]::InputBox("Enter your commit message:", "Commit Message", "Update firmware")
}

# If still no commit message, use default
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = "Update firmware"
}

# Verify GitHub CLI exists
if (-not (Test-Path $GhExePath)) {
    Write-Host "ERROR: GitHub CLI not found at: $GhExePath"
    Write-Host "Please install GitHub CLI from: https://cli.github.com/"
    exit 1
}

# Change to repository directory
Write-Host "Changing to repository directory..."
Set-Location -Path $RepoPath

# Verify git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Git is not installed or not in PATH"
    exit 1
}

# Stage all changes
Write-Host "Staging all changes..."
git add -A

# Commit changes
Write-Host "Committing changes with message: $CommitMessage"
git commit -m $CommitMessage

# Push to remote (triggers GitHub Actions workflow)
Write-Host "Pushing to remote..."
git push origin Main

# Wait for GitHub Actions to start the workflow
Write-Host "Waiting for GitHub Actions to start the workflow..."
Start-Sleep -Seconds 5

# Find the workflow run (with retry logic)
$maxRetries = 12  # 12 retries * 5 seconds = 60 seconds max wait
$retryCount = 0
$runId = $null

while ($retryCount -lt $maxRetries -and $null -eq $runId) {
    $retryCount++
    Write-Host "Checking for workflow run... (attempt $retryCount of $maxRetries)"
    
    # Get the latest run and filter for in-progress status
    $runs = & $GhExePath run list --limit 5 --json id,name,status,conclusion 2>$null | ConvertFrom-Json
    
    if ($runs -and $runs.Count -gt 0) {
        # Find the first in-progress run (most recent)
        $inProgressRun = $runs | Where-Object { $_.status -eq "in_progress" } | Select-Object -First 1
        
        if ($inProgressRun) {
            $runId = $inProgressRun.id
            Write-Host "Found workflow run: $($inProgressRun.name) (ID: $runId)"
            break
        }
    }
    
    if ($null -eq $runId) {
        Write-Host "No in-progress run found, waiting 5 seconds..."
        Start-Sleep -Seconds 5
    }
}

if ($null -eq $runId) {
    Write-Host "ERROR: Could not find a running workflow after 60 seconds"
    Write-Host "Please check your GitHub Actions and run manually if needed"
    exit 1
}

# Wait for the specific workflow run to complete
Write-Host "Waiting for workflow run $runId to complete..."
& $GhExePath run watch $runId

# Create timestamped subfolder for this build
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$buildFolder = Join-Path $BuildVersionsPath $timestamp
Write-Host "Creating build folder: $buildFolder"
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null

# Download the firmware artifact for the specific run
Write-Host "Downloading firmware artifact for run $runId..."
& $GhExePath run download $runId --dir $buildFolder

# Find and extract the ZIP file
Write-Host "Looking for firmware artifact..."
$zipFile = Get-ChildItem -Path $buildFolder -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($zipFile) {
    Write-Host "Found artifact: $($zipFile.Name)"
    
    # Extract the ZIP file
    Write-Host "Extracting firmware..."
    Expand-Archive -Path $zipFile.FullName -DestinationPath $buildFolder -Force
    
    Write-Host ""
    Write-Host "=== Build Complete ==="
    Write-Host "Firmware location: $buildFolder"
    
    # List extracted .uf2 files
    $uf2Files = Get-ChildItem -Path $buildFolder -Filter "*.uf2"
    if ($uf2Files) {
        Write-Host "Extracted .uf2 files:"
        foreach ($uf2 in $uf2Files) {
            Write-Host "  - $($uf2.Name)"
        }
    }
} else {
    Write-Host "WARNING: No ZIP artifact found in $buildFolder"
    Write-Host "Please check the GitHub Actions run manually."
}
