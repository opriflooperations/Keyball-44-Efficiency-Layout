# Build and Download Firmware Script
# This script builds the ZMK firmware and downloads it to the Keyball44

param(
    [string]$CommitMessage = "",
    [switch]$CommitOnly,
    [switch]$DownloadOnly
)

# Configuration - Update these paths as needed
$RepoPath = "C:\Code\KeyBall44 Keyboard Layout Setup\Keyball44 Backend Code\Keyball-44-Efficiency-Layout"
$BuildVersionsPath = "C:\Code\KeyBall44 Keyboard Layout Setup\Build Versions"

# Paths
$GhExePath = "C:\Program Files\GitHub CLI\gh.exe"

# Starting version for smart versioning
$StartingVersion = 82

Write-Host "=========================================="
Write-Host "Keyball44 Firmware Build Script"
Write-Host "=========================================="
if ($CommitOnly) {
    Write-Host "Mode: COMMIT ONLY (Ctrl+Shift+S)"
} elseif ($DownloadOnly) {
    Write-Host "Mode: DOWNLOAD ONLY (Ctrl+Shift+D)"
} else {
    Write-Host "Mode: COMMIT + DOWNLOAD (full workflow)"
}
Write-Host ""
Write-Host ""

# ==========================================
# DOWNLOAD-ONLY MODE: Skip commit, get latest build
# ==========================================
if ($DownloadOnly) {
    Write-Host "Mode: DOWNLOAD ONLY - Finding latest completed workflow..."
    
    # Verify GitHub CLI exists
    if (-not (Test-Path $GhExePath)) {
        Write-Host "ERROR: GitHub CLI not found at: $GhExePath"
        exit 1
    }
    
    # Change to repository directory
    Set-Location -Path $RepoPath
    
    # Get the latest successful workflow run
    Write-Host "Finding latest completed workflow..."
    $rawOutput = & $GhExePath run list --workflow build.yml --limit 5 --json name,status,conclusion,databaseId,headSha 2>&1
    
    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        Write-Host "ERROR: Could not get workflow runs"
        exit 1
    }
    
    $runs = $rawOutput | ConvertFrom-Json
    $runDbId = $null
    
    # Find the first completed/successful run
    foreach ($run in $runs) {
        Write-Host "  Run: databaseId=$($run.databaseId), status=$($run.status), conclusion=$($run.conclusion)"
        if ($run.status -eq "completed" -and $run.conclusion -eq "success") {
            $runDbId = $run.databaseId
            Write-Host "  Using latest completed run: $runDbId"
            break
        }
    }
    
    if ($null -eq $runDbId) {
        Write-Host "ERROR: No completed workflow runs found"
        exit 1
    }
    
    goto :DownloadArtifact
}

# ==========================================
# POPUP COMMIT MESSAGE INPUT (Windows Forms)
# ==========================================
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    # Gather changed files info
    $stagedFiles = git diff --staged --name-only 2>&1
    $unstagedFiles = git diff --name-only 2>&1
    $allFiles = @()
    if ($stagedFiles) { $allFiles += ($stagedFiles -split "`n" | Where-Object { $_ -ne "" }) }
    if ($unstagedFiles) { $allFiles += ($unstagedFiles -split "`n" | Where-Object { $_ -ne "" }) }
    $allFiles = $allFiles | Select-Object -Unique
    
    # Build changed files display text
    $filesInfo = ""
    if ($allFiles.Count -gt 0) {
        $filesInfo = "Changed files ($($allFiles.Count)):`n"
        foreach ($f in $allFiles) { $filesInfo += "  $f`n" }
    } else {
        $filesInfo = "No changes detected"
    }
    
    # Load Windows Forms assembly
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Commit Message"
    $form.Size = New-Object System.Drawing.Size(600, 320)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    
    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(15, 15)
    $titleLabel.Size = New-Object System.Drawing.Size(555, 25)
    $titleLabel.Text = "Enter commit message (Ctrl+Enter or Enter to submit):"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)
    
    # Changed files info label
    $filesLabel = New-Object System.Windows.Forms.Label
    $filesLabel.Location = New-Object System.Drawing.Point(15, 45)
    $filesLabel.Size = New-Object System.Drawing.Size(555, 60)
    $filesLabel.Text = $filesInfo
    $filesLabel.Font = New-Object System.Drawing.Font("Consolas", 9)
    $filesLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $form.Controls.Add($filesLabel)
    
    # TextBox for commit message
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(15, 110)
    $textBox.Size = New-Object System.Drawing.Size(555, 100)
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $textBox.AcceptsReturn = $true
    $textBox.AcceptsTab = $false
    $textBox.WordWrap = $true
    $textBox.Text = ""
    $textBox.Add_KeyDown({
        param($sender, $e)
        # Ctrl+Enter or Enter submits
        if (($e.KeyCode -eq "Return" -and $_.Modifiers -eq "Control") -or $e.KeyCode -eq "Return") {
            $script:dialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
    })
    $form.Controls.Add($textBox)
    
    # Hint label
    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Location = New-Object System.Drawing.Point(15, 215)
    $hintLabel.Size = New-Object System.Drawing.Size(555, 20)
    $hintLabel.Text = "Press Ctrl+Enter, Enter, or click Submit to commit"
    $hintLabel.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 130)
    $form.Controls.Add($hintLabel)
    
    # Submit button
    $submitButton = New-Object System.Windows.Forms.Button
    $submitButton.Location = New-Object System.Drawing.Point(435, 240)
    $submitButton.Size = New-Object System.Drawing.Size(135, 35)
    $submitButton.Text = "Submit"
    $submitButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $submitButton.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
    $submitButton.ForeColor = [System.Drawing.Color]::White
    $submitButton.FlatStyle = "Flat"
    $submitButton.Add_Click({
        $script:dialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($submitButton)
    
    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(295, 240)
    $cancelButton.Size = New-Object System.Drawing.Size(135, 35)
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    
    # Set form's CancelButton
    $form.CancelButton = $cancelButton
    
    # Initialize dialog result
    $script:dialogResult = [System.Windows.Forms.DialogResult]::Cancel
    
    # Show form and focus the textbox
    $form.Add_Shown({ $textBox.Focus() })
    $result = $form.ShowDialog()
    
    # Get the commit message
    $CommitMessage = $textBox.Text.Trim()
    
    # If cancelled or empty, use default
    if ([string]::IsNullOrWhiteSpace($CommitMessage) -or $dialogResult -eq [System.Windows.Forms.DialogResult]::Cancel) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        $CommitMessage = "Update firmware [$timestamp]"
        Write-Host "Using default: $CommitMessage"
    } else {
        Write-Host "Commit message: $CommitMessage"
    }
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
$branch = git rev-parse --abbrev-ref HEAD 2>&1
Write-Host "Current branch: $branch"
git push origin $branch

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
# SKIP DOWNLOAD IF IN COMMIT-ONLY MODE
# ==========================================
if ($CommitOnly) {
    Write-Host ""
    Write-Host "=== Commit Complete (Ctrl+Shift+S mode) ==="
    Write-Host "Workflow triggered: $runDbId"
    Write-Host "Build will complete in GitHub Actions."
    Write-Host "Press Ctrl+Shift+D to download when ready."
    exit 0
}

# ==========================================
# DOWNLOAD ARTIFACT LABEL (for goto from DownloadOnly mode)
# ==========================================
:DownloadArtifact

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
