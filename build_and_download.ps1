# Build and Download Firmware Script
# This script builds the ZMK firmware and downloads it to the Keyball44

param(
    [string]$CommitMessage = ""
)

# Configuration - Update these paths as needed
$RepoPath = "C:\Code\KeyBall44 Keyboard Layout Setup\Keyball44 Backend Code\Keyball-44-Efficiency-Layout"
$BuildVersionsPath = "C:\Code\KeyBall44 Keyboard Layout Setup\Build Versions"

# Paths
$GhExePath = "C:\Program Files\GitHub CLI\gh.exe"

# Starting version for smart versioning
$StartingVersion = 82

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

# ==========================================
# ZERO-FAILURE WORKFLOW MONITORING
# ==========================================

# Find the workflow run using direct databaseId approach
$maxRetries = 12  # 12 retries * 5 seconds = 60 seconds max wait
$retryCount = 0
$runDbId = $null

while ($retryCount -lt $maxRetries -and $null -eq $runDbId) {
    $retryCount++
    
    # RULE 1: Echo Rule - Print exact command before execution
    $commandToRun = "& `"$GhExePath`" run list --workflow build.yml --limit 1 --json name,status,conclusion,databaseId"
    Write-Host "Executing: $commandToRun"
    
    # RULE 2: Direct Output Check - Capture and print raw text BEFORE parsing
    $rawOutput = & $GhExePath run list --workflow build.yml --limit 1 --json name,status,conclusion,databaseId 2>&1
    
    # Print raw output for transparency
    Write-Host "Raw GH CLI output: $rawOutput"
    
    # Check if raw output is empty
    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        Write-Host "WARNING: GH CLI returned empty output - authentication may be required"
        Write-Host "Please run 'gh auth login' in your terminal if not already authenticated"
    } else {
        # RULE 3: Stop Status Filter - Just get first item, check for databaseId existence
        $runs = $rawOutput | ConvertFrom-Json
        
        if ($runs -and $runs.Count -gt 0) {
            $latestRun = $runs[0]
            
            # RULE 4: Use Database ID - Extract databaseId and watch immediately
            if ($latestRun.databaseId) {
                $runDbId = $latestRun.databaseId
                Write-Host "Found workflow run: $($latestRun.name) (databaseId: $runDbId, Status: $($latestRun.status), Conclusion: $($latestRun.conclusion))"
                Write-Host "Starting to watch the run..."
                break
            } else {
                Write-Host "First run found but has no databaseId, waiting 5 seconds..."
            }
        }
    }
    
    if ($null -eq $runDbId) {
        Write-Host "No run with databaseId found yet, waiting 5 seconds... (attempt $retryCount of $maxRetries)"
        Start-Sleep -Seconds 5
    }
}

if ($null -eq $runDbId) {
    Write-Host "ERROR: Could not find a workflow run with databaseId after 60 seconds"
    Write-Host "Please check your GitHub Actions and run manually if needed"
    exit 1
}

# Wait for the specific workflow run to complete
Write-Host "Waiting for workflow run $runDbId to complete..."
& $GhExePath run watch $runDbId

# ==========================================
# SMART VERSIONING (v82+)
# ==========================================

# Ensure the build versions directory exists
if (-not (Test-Path $BuildVersionsPath)) {
    Write-Host "Creating build versions directory: $BuildVersionsPath"
    New-Item -ItemType Directory -Path $BuildVersionsPath -Force | Out-Null
}

# Find all version folders (folders starting with 'v')
$versionFolders = Get-ChildItem -Path $BuildVersionsPath -Directory | Where-Object { $_.Name -match '^v\d+$' }

$nextVersionNumber = $StartingVersion

if ($versionFolders -and $versionFolders.Count -gt 0) {
    # Extract version numbers and find the highest
    $versionNumbers = $versionFolders | ForEach-Object {
        [int]($_.Name -replace 'v', '')
    }
    $highestVersion = $versionNumbers | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
    $nextVersionNumber = $highestVersion + 1
    Write-Host "Found existing versions. Highest version: v$highestVersion"
}

$versionFolderName = "v$nextVersionNumber"
$buildFolder = Join-Path $BuildVersionsPath $versionFolderName

Write-Host "Creating version folder: $buildFolder"
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null

# Download the firmware artifact for the specific run
Write-Host "Downloading firmware artifact for run $runDbId..."
& $GhExePath run download $runDbId --dir $buildFolder

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
    
    # Search for .uf2 files in the new folder
    $uf2Files = Get-ChildItem -Path $buildFolder -Filter "*.uf2" -Recurse
    if ($uf2Files) {
        Write-Host "Found .uf2 files:"
        foreach ($uf2 in $uf2Files) {
            Write-Host "  - $($uf2.Name)"
        }
    }
    
    # Auto-Open: Run explorer.exe on the new version folder
    Write-Host ""
    Write-Host "Opening build folder in Explorer..."
    explorer.exe $buildFolder
} else {
    Write-Host "WARNING: No ZIP artifact found in $buildFolder"
    Write-Host "Please check the GitHub Actions run manually."
    
    # Still open the folder in case there are other files
    Write-Host "Opening build folder in Explorer anyway..."
    explorer.exe $buildFolder
}