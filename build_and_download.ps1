# Build and Download Firmware Script
# This script builds the ZMK firmware and downloads it to the Keyball44

param(
    [string]$CommitMessage = ""
)

# Configuration - Update these paths as needed
$RepoPath = "C:\Code\KeyBall44 Keyboard Layout Setup\Keyball44 Backend Code\Keyball-44-Efficiency-Layout"
$BuildVersionsPath = "$env:USERPROFILE\Downloads"

# Paths
$GhExePath = "$env:LOCALAPPDATA\GitHubCli\bin\gh.exe"

# Show commit message popup if no message provided
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Commit Message"
    $form.Width = 500
    $form.Height = 200
    $form.StartPosition = "CenterScreen"
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter your commit message:"
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $label.AutoSize = $true
    $form.Controls.Add($label)
    
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 40)
    $textBox.Width = 460
    $textBox.Height = 100
    $textBox.Multiline = $true
    $form.Controls.Add($textBox)
    
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $okButton.Location = New-Object System.Drawing.Point(195, 130)
    $form.Controls.Add($okButton)
    
    $form.AcceptButton = $okButton
    
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $CommitMessage = $textBox.Text
    }
    
    $form.Dispose()
}

# If still no commit message, use default
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = "Update firmware"
}

# Change to repository directory
Write-Host "Changing to repository directory..."
Set-Location -Path $RepoPath

# Stage all changes
Write-Host "Staging all changes..."
git add -A

# Commit changes
Write-Host "Committing changes with message: $CommitMessage"
git commit -m $CommitMessage

# Push to remote
Write-Host "Pushing to remote..."
git push origin Main

# Build the firmware
Write-Host "Building firmware..."
west build -b keyball44 --board-dir . --build-dir build

# Find the firmware file
Write-Host "Looking for firmware file..."
$firmwareFile = Get-ChildItem -Path "$RepoPath\build\zephyr" -Filter "*.zmk.uf2" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($firmwareFile) {
    Write-Host "Found firmware: $($firmwareFile.Name)"
    
    # Copy to Downloads
    $destPath = Join-Path $BuildVersionsPath $firmwareFile.Name
    Copy-Item -Path $firmwareFile.FullName -Destination $destPath -Force
    Write-Host "Copied firmware to: $destPath"
    
    # Download via GitHub CLI
    if (Test-Path $GhExePath) {
        Write-Host "Opening download location..."
        & $GhExePath release view --web
    } else {
        Write-Host "gh.exe not found at: $GhExePath"
        Write-Host "Please download firmware manually from: $firmwareFile.FullName"
    }
} else {
    Write-Host "ERROR: No firmware file found!"
    Write-Host "Build may have failed. Check the output above for errors."
}