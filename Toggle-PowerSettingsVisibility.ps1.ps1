# Warning AI Slop, although tested and working
function Toggle-PowerSettingsVisibility {
    $Title = 'Select option(s) to toggle visibility'
    $PowerSettings = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
    
    # Load required assemblies for Windows Forms
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(700, 500)
    $form.StartPosition = 'CenterScreen'
    
    # Create a panel with scrolling for the settings
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(10, 10)
    $panel.Size = New-Object System.Drawing.Size(660, 400)
    $panel.AutoScroll = $true
    $form.Controls.Add($panel)
    
    # Get power settings
    $powerOptions = Get-ChildItem $PowerSettings -Recurse | ? Property -contains 'Attributes' | Get-ItemProperty
    
    # Track all options with their current state and comboboxes
    $settingsCollection = @()
    
    # Add settings to the panel
    $yPos = 10
    foreach ($option in $powerOptions) {
        # Determine current visibility
        $isVisible = ($option.Attributes -band 0x00000001) -eq 0
        $currentState = if($isVisible) { "Visible" } else { "Hidden" }
        
        # Get display name safely
        $displayName = $option.PSChildName
        if ($null -ne $option.FriendlyName) {
            try {
                $nameParts = $option.FriendlyName.Split(',')
                if ($nameParts.Count -gt 0) {
                    $displayName = $nameParts[-1].Trim()
                }
            } catch {
                # Keep using PSChildName if there's an error
            }
        }
        
        # Create a label for the setting name
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point(10, $yPos)
        $label.Size = New-Object System.Drawing.Size(400, 32)
        $label.Text = $displayName
        $panel.Controls.Add($label)
        
        # Create a dropdown for the visibility options
        $dropdown = New-Object System.Windows.Forms.ComboBox
        $dropdown.Location = New-Object System.Drawing.Point(420, $yPos)
        $dropdown.Size = New-Object System.Drawing.Size(200, 25)
        $dropdown.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        [void]$dropdown.Items.Add("No Change")
        [void]$dropdown.Items.Add("Make Visible")
        [void]$dropdown.Items.Add("Make Hidden")
        $dropdown.SelectedItem = "No Change"
        $panel.Controls.Add($dropdown)
        
        # Store the setting and its control
        $settingsCollection += [PSCustomObject]@{
            Setting = $option
            Dropdown = $dropdown
            CurrentState = $currentState
            Path = "$PowerSettings\*\$($option.PSChildName)"
        }
        
        $yPos += 40
    }
    
    # Create OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(520, 420)
    $okButton.Size = New-Object System.Drawing.Size(75, 23)
    $okButton.Text = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)
    
    # Create Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(600, 420)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 23)
    $cancelButton.Text = 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)
    
    # Show the form and wait for a result
    $result = $form.ShowDialog()
    
    # Process the selections if the user clicked OK
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Create a summary of changes to apply
        $changesToApply = $settingsCollection | Where-Object { $_.Dropdown.SelectedItem -ne "No Change" }
        
        # If there are changes, show a summary and confirm once
        if ($changesToApply.Count -gt 0) {
            $summaryForm = New-Object System.Windows.Forms.Form
            $summaryForm.Text = "Confirm Changes"
            $summaryForm.Size = New-Object System.Drawing.Size(600, 400)
            $summaryForm.StartPosition = 'CenterScreen'
            
            $summaryLabel = New-Object System.Windows.Forms.Label
            $summaryLabel.Location = New-Object System.Drawing.Point(10, 10)
            $summaryLabel.Size = New-Object System.Drawing.Size(560, 30)
            $summaryLabel.Text = "The following changes will be applied:"
            $summaryForm.Controls.Add($summaryLabel)
            
            $summaryTextBox = New-Object System.Windows.Forms.RichTextBox
            $summaryTextBox.Location = New-Object System.Drawing.Point(10, 50)
            $summaryTextBox.Size = New-Object System.Drawing.Size(560, 250)
            $summaryTextBox.ReadOnly = $true
            
            foreach ($change in $changesToApply) {
                $summaryTextBox.AppendText("• Change $($change.Setting.PSChildName) from $($change.CurrentState) to $($change.Dropdown.SelectedItem)`r`n")
            }
            
            $summaryForm.Controls.Add($summaryTextBox)
            
            $confirmButton = New-Object System.Windows.Forms.Button
            $confirmButton.Location = New-Object System.Drawing.Point(400, 320)
            $confirmButton.Size = New-Object System.Drawing.Size(75, 23)
            $confirmButton.Text = 'Apply'
            $confirmButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $summaryForm.AcceptButton = $confirmButton
            $summaryForm.Controls.Add($confirmButton)
            
            $cancelSummaryButton = New-Object System.Windows.Forms.Button
            $cancelSummaryButton.Location = New-Object System.Drawing.Point(490, 320)
            $cancelSummaryButton.Size = New-Object System.Drawing.Size(75, 23)
            $cancelSummaryButton.Text = 'Cancel'
            $cancelSummaryButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $summaryForm.CancelButton = $cancelSummaryButton
            $summaryForm.Controls.Add($cancelSummaryButton)
            
            $confirmResult = $summaryForm.ShowDialog()
            
            if ($confirmResult -eq [System.Windows.Forms.DialogResult]::OK) {
                # Apply all changes without individual prompts
                foreach ($item in $changesToApply) {
                    $makeVisible = $item.Dropdown.SelectedItem -eq "Make Visible"
                    $newValue = if ($makeVisible) { $item.Setting.Attributes -band -bnot 1 } else { $item.Setting.Attributes -bor 1 }
                    
                    # Safely resolve the path
                    $resolvedPath = $null
                    try {
                        $resolvedPath = Resolve-Path $item.Path -ErrorAction Stop
                    } catch {
                        Write-Host "Error resolving path for $($item.Setting.PSChildName): $_" -ForegroundColor Red
                        continue
                    }
                    
                    if ($null -ne $resolvedPath) {
                        Write-Host "Changing $($item.Setting.PSChildName) from $($item.CurrentState) to $($item.Dropdown.SelectedItem)"
                        Set-ItemProperty -Path $resolvedPath -Name "Attributes" -Value $newValue -Force
                    }
                }
                
                Write-Host "All changes applied successfully!" -ForegroundColor Green
            } else {
                Write-Host "Changes cancelled by user." -ForegroundColor Yellow
            }
        } else {
            Write-Host "No changes selected." -ForegroundColor Yellow
        }
    }
}
