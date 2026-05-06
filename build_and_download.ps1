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

# Generate AI commit message using git diff analysis
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    Write-Host "Analyzing changes for commit message..."
    
    # Get all changes (staged + unstaged)
    $stagedFiles = git diff --staged --name-only 2>&1
    $unstagedFiles = git diff --name-only 2>&1
    
    # Combine all changed files
    $allFiles = @()
    if ($stagedFiles) { $allFiles += ($stagedFiles -split "`n" | Where-Object { $_ -ne "" }) }
    if ($unstagedFiles) { $allFiles += ($unstagedFiles -split "`n" | Where-Object { $_ -ne "" }) }
    $allFiles = $allFiles | Select-Object -Unique
    
    if ($allFiles.Count -eq 0) {
        $CommitMessage = "Update firmware configuration"
    } else {
        # Get the actual diff content for smart analysis
        $diffContent = git diff --staged 2>&1
        if (-not $diffContent) { $diffContent = git diff 2>&1 }
        
        # Analyze the diff to determine what changed
        $changeDescription = ""
        
        # Check for specific patterns in the diff
        if ($diffContent -match "DTgid|DT\(KC\)") {
            $changeDescription = "Update key assignments"
        }
        if ($diffContent -match "MO\(|TG\(|OSL\(") {
            $changeDescription += " layer changes"
        }
        if ($diffContent -match "&keyball") {
            $changeDescription += " keyball settings"
        }
        if ($diffContent -match "TAP_DANCE|MT\(") {
            $changeDescription += " tap/hold mods"
        }
        if ($diffContent -match "&bt BT_") {
            $changeDescription += " bluetooth config"
        }
        
        # Determine primary change type from file names
        $keymapFiles = $allFiles | Where-Object { $_ -match "keymap" }
        $configFiles = $allFiles | Where-Object { $_ -match "\.conf$|\.yaml$|\.yml$|\.overlay$" }
        $devFiles = $allFiles | Where-Object { $_ -match "build\.yaml|\.ps1$|build\.yml" }
        
        if ($devFiles) {
            $CommitMessage = "Update build system"
        } elseif ($keymapFiles -and $configFiles) {
            if ($changeDescription) {
                $CommitMessage = "Update layout $changeDescription"
            } else {
                $CommitMessage = "Update keyboard configuration and keymap"
            }
        } elseif ($keymapFiles) {
            if ($changeDescription) {
                $CommitMessage = "Update keymap $changeDescription"
            } else {
                $CommitMessage = "Update keymap layout"
            }
        } elseif ($configFiles) {
            if ($changeDescription) {
                $CommitMessage = "Update config $changeDescription"
            } else {
                $CommitMessage = "Update keyboard configuration"
            }
        } else {
            $CommitMessage = "Update source files"
        }
        
        # Add smart suffix based on diff size
        $linesAdded = ([regex]::Matches($diffContent, "^\+[^+]" , [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
        $linesRemoved = ([regex]::Matches($diffContent, "^-[^-]" , [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
        
        if ($linesAdded -gt 50 -or $linesRemoved -gt 30) {
            $CommitMessage += " [major]"
        } elseif ($linesAdded -gt 20 -or $linesRemoved -gt 15) {
            $CommitMessage += " [minor]"
        }
    }
    
    # Add timestamp to avoid duplicate commits
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $CommitMessage = "$CommitMessage [$timestamp]"
    
    Write-Host "AI-generated commit: $CommitMessage"
    Write-Host "Changed files: $($allFiles.Count)"
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

# ==========================================
# WAIT FOR NEW WORKFLOW RUN
# ==========================================

# Get the commit SHA that was just pushed
$commitSha = git rev-parse HEAD 2>&1
Write-Host "Current commit SHA: $commitSha"

# Wait for GitHub Actions to start the NEW workflow (in_progress status)
Write-Host "Waiting for GitHub Actions to start the NEW workflow run..."
Start-Sleep -Seconds 8

$maxRetries = 24  # 24 retries * 5 seconds = 120 seconds max wait
$retryCount = 0
$runDbId = $null

while ($retryCount -lt $maxRetries -and $null -eq $runDbId) {
    $retryCount++
    
    # Get the latest workflow runs with status
    Write-Host "Checking for workflow runs... (attempt $retryCount of $maxRetries)"
    
    $rawOutput = & $GhExePath run list --workflow build.yml --limit 3 --json name,status,conclusion,databaseId,headSha 2>&1
    
    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        Write-Host "  GH CLI returned empty output - checking authentication..."
    } else {
        $runs = $rawOutput | ConvertFrom-Json
        
        if ($runs -and $runs.Count -gt 0) {
            Write-Host "  Found $($runs.Count) recent run(s)"
            
            # Look for a run that is in_progress AND matches our commit SHA
            foreach ($run in $runs) {
                Write-Host "    Run: databaseId=$($run.databaseId), status=$($run.status), conclusion=$($run.conclusion), headSha=$($run.headSha)"
                
                # PRIMARY: Look for in_progress run with matching commit (NEW run we just triggered)
                if ($run.status -eq "in_progress" -and $run.headSha -eq $commitSha) {
                    $runDbId = $run.databaseId
                    Write-Host "  FOUND NEW RUN (in_progress) matching current commit SHA: $runDbId"
                    break
                }
                
                # SECONDARY: If no in_progress, check for queued run with matching commit
                if ($run.status -eq "queued" -and $run.headSha -eq $run.headSha) {
                    $runDbId = $run.databaseId
                    Write-Host "  FOUND QUEUED RUN matching current commit SHA: $runDbId"
                    break
                }
            }
            
            # FALLBACK: If we found ANY recent in_progress run (may be from same push)
            if ($null -eq $runDbId) {
                $inProgressRun = $runs | Where-Object { $_.status -eq "in_progress" } | Select-Object -First 1
                if ($inProgressRun -and $inProgressRun.databaseId) {
                    $runDbId = $inProgressRun.databaseId
                    Write-Host "  Using in_progress run: $runDbId (may be from this push)"
                }
            }
        }
    }
    
    if ($null -eq $runDbId) {
        Write-Host "  Waiting for new workflow run... (attempt $retryCount of $maxRetries)"
        Start-Sleep -Seconds 5
    }
}

if ($null -eq $runDbId) {
    Write-Host "ERROR: Could not find a new workflow run after 120 seconds"
    Write-Host "Please check your GitHub Actions dashboard manually"
    exit 1
}

Write-Host "Found NEW workflow run to watch: databaseId=$runDbId"

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
    # Extract version numbers using regex to capture only the numeric part
    $versionNumbers = $versionFolders | ForEach-Object {
        if ($_.Name -match '^v(\d+)$') {
            [int]$matches[1]
        }
    } | Where-Object { $null -ne $_ }
    
    if ($versionNumbers -and $versionNumbers.Count -gt 0) {
        # Use integer comparison to ensure 100 > 81
        $highestVersion = ($versionNumbers | Measure-Object -Maximum).Maximum
        
        # Enforce v82 floor
        if ($highestVersion -lt $StartingVersion) {
            $highestVersion = ($StartingVersion - 1)
        }
        
        $nextVersionNumber = $highestVersion + 1
        Write-Host "Found existing versions. Highest version: v$highestVersion"
    }
}

$versionFolderName = "v$nextVersionNumber"
$buildFolder = Join-Path $BuildVersionsPath $versionFolderName

Write-Host "Creating version folder: $buildFolder"
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null

# Download the firmware artifact for the specific run
Write-Host "Downloading firmware artifact for run $runDbId..."
# Get the artifact download URL using gh API
$artifacts = & $GhExePath api "repos/opriflooperations/Keyball-44-Efficiency-Layout/actions/runs/$runDbId/artifacts" 2>&1 | ConvertFrom-Json
if ($artifacts -and $artifacts.artifacts) {
    $firmwareArtifact = $artifacts.artifacts | Where-Object { $_.name -like "*firmware*" } | Select-Object -First 1
    if ($firmwareArtifact) {
        Write-Host "Found artifact: $($firmwareArtifact.name) (ID: $($firmwareArtifact.id))"
        $zipPath = Join-Path $buildFolder "firmware.zip"
        Write-Host "Downloading artifact to $zipPath using gh api..."
        
        # Use gh api to download with proper authentication
        # The -H Accept header and -o output are critical for binary artifacts
        & $GhExePath api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" `
            "repos/opriflooperations/Keyball-44-Efficiency-Layout/actions/artifacts/$($firmwareArtifact.id)/zip" `
            -o $zipPath 2>&1
        
        # Wait for download to complete
        $maxDownloadWait = 60
        $downloaded = 0
        while ($downloaded -lt $maxDownloadWait -and (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1000)) {
            Start-Sleep -Seconds 1
            $downloaded++
        }
        
        if (Test-Path $zipPath) {
            $fileSize = (Get-Item $zipPath).Length
            Write-Host "Download complete. Size: $fileSize bytes"
            if ($fileSize -lt 1000) {
                Write-Host "WARNING: File seems too small, checking contents..."
                $content = Get-Content $zipPath -Raw -ErrorAction SilentlyContinue
                if ($content -and $content.Length -lt 500) {
                    Write-Host "Download appears to be text (likely error): $content"
                }
            }
        } else {
            Write-Host "ERROR: Download failed"
        }
    } else {
        Write-Host "ERROR: No firmware artifact found with correct name pattern"
    }
} else {
    Write-Host "No firmware artifact found with 'firmware' pattern, checking all artifacts..."
    $allArtifacts = & $GhExePath api "repos/opriflooperations/Keyball-44-Efficiency-Layout/actions/runs/$runDbId/artifacts" 2>&1 | ConvertFrom-Json
    if ($allArtifacts -and $allArtifacts.artifacts -and $allArtifacts.artifacts.Count -gt 0) {
        Write-Host "Found $($allArtifacts.artifacts.Count) artifact(s):"
        foreach ($art in $allArtifacts.artifacts) {
            Write-Host "  - $($art.name) (ID: $($art.id))"
        }
        
        # Get the first artifact (which should be the firmware zip)
        $firstArtifact = $allArtifacts.artifacts[0]
        $zipPath = Join-Path $buildFolder "firmware.zip"
        Write-Host "Downloading first artifact: $($firstArtifact.name) using gh api..."
        
        # Use gh api to download with proper authentication
        & $GhExePath api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" `
            "repos/opriflooperations/Keyball-44-Efficiency-Layout/actions/artifacts/$($firstArtifact.id)/zip" `
            -o $zipPath 2>&1
        
        $maxDownloadWait = 60
        $downloaded = 0
        while ($downloaded -lt $maxDownloadWait -and (-not (Test-Path $zipPath) -or (Get-Item $zipPath).Length -lt 1000)) {
            Start-Sleep -Seconds 1
            $downloaded++
        }
    } else {
        Write-Host "ERROR: No artifacts found for this run"
    }
}

# Find and extract the ZIP file
Write-Host "Looking for firmware artifact..."
$zipFile = Get-ChildItem -Path $buildFolder -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($zipFile) {
    Write-Host "Found artifact: $($zipFile.Name)"
    Write-Host "Size: $($zipFile.Length) bytes"
    
    # Extract the ZIP file using Shell.Application for better binary handling
    Write-Host "Extracting firmware using Shell.Application..."
    try {
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.Namespace($zipFile.FullName)
        $destination = $shell.Namespace($buildFolder)
        $destination.CopyHere($zip.Items(), 0x14)  # 0x14 = NoAutoRename + NoConfirmSuppress
        
        # Wait for extraction to complete (Shell.Application is async)
        Write-Host "Waiting for extraction to complete..."
        $maxWait = 30
        $waited = 0
        $expectedFiles = @("keyball44_left-nice_nano_v2-zmk.uf2", "keyball44_right-nice_nano_v2-zmk.uf2")
        $allFound = $false
        
        while ($waited -lt $maxWait -and -not $allFound) {
            Start-Sleep -Seconds 1
            $waited++
            $allFound = $true
            foreach ($expected in $expectedFiles) {
                $found = Get-ChildItem -Path $buildFolder -Filter $expected -Recurse -ErrorAction SilentlyContinue
                if (-not $found) {
                    $allFound = $false
                    break
                }
            }
            if (-not $allFound) {
                Write-Host "  Waiting... ($waited seconds)"
            }
        }
        
        if ($allFound) {
            Write-Host "Extraction complete ($waited seconds)."
        } else {
            Write-Host "WARNING: Extraction may not be complete after $maxWait seconds."
        }
    } catch {
        Write-Host "Shell extraction failed, trying Expand-Archive..."
        Expand-Archive -Path $zipFile.FullName -DestinationPath $buildFolder -Force
    }
    
    Write-Host ""
    Write-Host "=== Build Complete ==="
    Write-Host "Firmware location: $buildFolder"
    
    # Search for .uf2 files in the new folder
    $uf2Files = Get-ChildItem -Path $buildFolder -Filter "*.uf2" -Recurse
    if ($uf2Files) {
        Write-Host "Found .uf2 files:"
        foreach ($uf2 in $uf2Files) {
            Write-Host "  - $($uf2.FullName)"
            
            # Calculate SHA256 checksum for verification
            $sha256 = Get-FileHash -Path $uf2.FullName -Algorithm SHA256
            Write-Host "    Size: $($uf2.Length) bytes, Attrs: $($uf2.Attributes)"
            Write-Host "    SHA256: $($sha256.Hash)"
            
            # Remove any Zone.Identifier (NTFS alternate stream) that might block the file
            $zoneIdPath = "$($uf2.FullName):Zone.Identifier"
            if (Test-Path $zoneIdPath) {
                Write-Host "    Removing Zone.Identifier..."
                Remove-Item $zoneIdPath -Force -ErrorAction SilentlyContinue
            }
            
            # Reset file attributes to normal
            $uf2.Attributes = 'Normal'
            Write-Host "    Reset file attributes to Normal"
            
            # Copy to clipboard for easy comparison
            Write-Host "    SHA256 copied to clipboard for comparison with manual download."
            Set-Clipboard -Value $sha256.Hash
        }
        
        # Debug: List all files in the build folder
        Write-Host ""
        Write-Host "=== Folder Contents ==="
        Get-ChildItem -Path $buildFolder -Recurse | ForEach-Object {
            Write-Host "  $($_.FullName) ($($_.Length) bytes, attrs: $($_.Attributes))"
        }
        
        Write-Host ""
        Write-Host "TIP: Compare the SHA256 hash above with a manually downloaded .uf2 file"
        Write-Host "using: Get-FileHash -Path 'path\to\file.uf2' -Algorithm SHA256"
    }
    
    # Auto-Open: Run explorer.exe on the new version folder
    Write-Host ""
    Write-Host "Opening build folder in Explorer..."
    explorer.exe $buildFolder
} else {
    Write-Host "WARNING: No ZIP artifact found in $buildFolder"
    Write-Host "Please check the GitHub Actions run manually."
    
    # Debug: List what IS in the folder
    Write-Host ""
    Write-Host "=== Actual Folder Contents ==="
    if (Test-Path $buildFolder) {
        Get-ChildItem -Path $buildFolder -Recurse | ForEach-Object {
            Write-Host "  $($_.Name) ($($_.Length) bytes, attrs: $($_.Attributes))"
        }
    } else {
        Write-Host "  (folder does not exist)"
    }
    
    # Still open the folder in case there are other files
    Write-Host "Opening build folder in Explorer anyway..."
    explorer.exe $buildFolder
}
