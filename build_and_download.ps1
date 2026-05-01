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

# Wait for GitHub Actions workflow to complete
Write-Host "Waiting for GitHub Actions workflow to complete..."
& $GhExePath run watch

# Create timestamped subfolder for this build
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$buildFolder = Join-Path $BuildVersionsPath $timestamp
Write-Host "Creating build folder: $buildFolder"
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null

# Download the firmware artifact
Write-Host "Downloading firmware artifact..."
& $GhExePath run download latest --dir $buildFolder

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
