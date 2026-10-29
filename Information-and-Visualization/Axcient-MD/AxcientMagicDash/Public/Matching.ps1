function Get-AmdMatchingId {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    $parsed = 0L
    if ($null -eq $Value -or -not [int64]::TryParse(
        [string]$Value,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    ) -or $parsed -le 0) {
        return $null
    }
    return $parsed
}

function Convert-AmdComparableCompanyName {
    [CmdletBinding()]
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    return [regex]::Replace($Name.Trim(), '[^\p{L}\p{Nd}]+', '').ToLowerInvariant()
}

function Update-AmdMatchExclusions {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$ExistingExclusions = @(),
        [Alias('Matches')]
        [AllowNull()][object[]]$CurrentMatches = @(),
        [AllowNull()][object[]]$Operations = @()
    )

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(ConvertTo-AmdAutoMatchExclusions -InputExclusions $ExistingExclusions)) { $result.Add($item) }
    foreach ($operation in @($Operations | Where-Object Action -eq 'Delete')) {
        $exists = @($result | Where-Object {
            [int64]$_.axcientId -eq [int64]$operation.AxcientId -and
            [int64]$_.huduID -eq [int64]$operation.SourceHuduId
        }).Count -gt 0
        if (-not $exists) {
            $result.Add([pscustomobject]@{
                axcientId = [int64]$operation.AxcientId
                huduID    = [int64]$operation.SourceHuduId
            })
        }
    }
    foreach ($matchItem in @($CurrentMatches)) {
        foreach ($item in @($result | Where-Object {
            [int64]$_.axcientId -eq [int64]$matchItem.axcientId -and
            [int64]$_.huduID -eq [int64]$matchItem.huduID
        })) {
            $null = $result.Remove($item)
        }
    }
    return @($result)
}

function Update-AmdAutomaticMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$HuduCompanies,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AxcientClients,
        [Alias('Matches')]
        [AllowNull()][object[]]$ExistingMatches = @(),
        [AllowNull()][object[]]$Exclusions = @()
    )

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($match in @($ExistingMatches)) {
        if ($null -ne $match) { $result.Add($match) }
    }

    $usedHudu = [System.Collections.Generic.HashSet[int64]]::new()
    $usedAxcient = [System.Collections.Generic.HashSet[int64]]::new()
    foreach ($match in $result) {
        $null = $usedHudu.Add([int64]$match.huduID)
        $null = $usedAxcient.Add([int64]$match.axcientId)
    }

    $clientsByName = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($client in @($AxcientClients)) {
        if ($null -eq (Get-AmdMatchingId $client.id)) { continue }
        $name = [string]$client.name
        if (-not $clientsByName.ContainsKey($name)) {
            $clientsByName[$name] = [System.Collections.Generic.List[object]]::new()
        }
        $clientsByName[$name].Add($client)
    }
    $companiesByName = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($company in @($HuduCompanies)) {
        if ($null -eq (Get-AmdMatchingId $company.id)) { continue }
        $name = [string]$company.name
        if (-not $companiesByName.ContainsKey($name)) {
            $companiesByName[$name] = [System.Collections.Generic.List[object]]::new()
        }
        $companiesByName[$name].Add($company)
    }
    $excludedPairs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($exclusion in @($Exclusions)) {
        $excludedAxcientId = Get-AmdMatchingId $exclusion.axcientId
        $excludedHuduId = Get-AmdMatchingId $exclusion.huduID
        if ($null -ne $excludedAxcientId -and $null -ne $excludedHuduId) {
            $null = $excludedPairs.Add("$excludedAxcientId`:$excludedHuduId")
        }
    }

    foreach ($client in @($AxcientClients | Sort-Object name, id)) {
        $clientId = Get-AmdMatchingId $client.id
        if ($null -eq $clientId) { continue }
        if ($usedAxcient.Contains($clientId)) { continue }
        $clientName = [string]$client.name
        if (-not $clientsByName.ContainsKey($clientName) -or
            $clientsByName[$clientName].Count -ne 1) {
            continue
        }

        if (-not $companiesByName.ContainsKey($clientName) -or
            $companiesByName[$clientName].Count -ne 1) {
            continue
        }
        $company = $companiesByName[$clientName][0]
        $companyId = Get-AmdMatchingId $company.id
        if ($usedHudu.Contains($companyId) -or
            $excludedPairs.Contains("$clientId`:$companyId")) {
            continue
        }
        $result.Add([pscustomobject]@{
            name      = [string]$client.name
            axcientId = $clientId
            huduID    = $companyId
        })
        $null = $usedHudu.Add($companyId)
        $null = $usedAxcient.Add($clientId)
    }

    return @($result)
}

function New-AmdMatchRows {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$HuduCompanies = @(),
        [AllowNull()][object[]]$AxcientClients = @(),
        [Alias('Matches')]
        [AllowNull()][object[]]$ExistingMatches = @()
    )

    $huduById = @{}
    foreach ($company in @($HuduCompanies)) {
        $companyId = Get-AmdMatchingId $company.id
        if ($null -ne $companyId) { $huduById[[string]$companyId] = $company }
    }
    $axcientById = @{}
    foreach ($client in @($AxcientClients)) {
        $clientId = Get-AmdMatchingId $client.id
        if ($null -ne $clientId) { $axcientById[[string]$clientId] = $client }
    }

    $usedHudu = [System.Collections.Generic.HashSet[int64]]::new()
    $usedAxcient = [System.Collections.Generic.HashSet[int64]]::new()
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($match in @($ExistingMatches)) {
        if ($null -eq $match) { continue }
        $huduId = [int64]$match.huduID
        $axcientId = [int64]$match.axcientId
        $company = $huduById[[string]$huduId]
        $client = $axcientById[[string]$axcientId]
        $null = $usedHudu.Add($huduId)
        $null = $usedAxcient.Add($axcientId)

        $isStale = $null -eq $company -or $null -eq $client
        $huduName = if ($company) { [string]$company.name } else { '[Missing Hudu company]' }
        $axcientName = if ($client) { [string]$client.name } elseif ($match.name) { "[Missing] $($match.name)" } else { '[Missing Axcient client]' }
        $rows.Add([pscustomobject]@{
            Kind           = if ($isStale) { 'Stale' } else { 'Matched' }
            HuduName       = $huduName
            HuduId         = $huduId
            HuduExists     = $null -ne $company
            HuduDisplay    = "$huduName (ID $huduId)"
            AxcientName    = $axcientName
            AxcientId      = $axcientId
            AxcientExists  = $null -ne $client
            AxcientDisplay = "$axcientName (ID $axcientId)"
            MatchedDisplay = if ($isStale) { '✕ Stale match' } else { '✓ Matched' }
            MatchColor     = if ($isStale) { '#E0A44F' } else { '#3FB27F' }
            Connection     = if ($isStale) { 'Missing endpoint — review this match' } else { "$huduName ↔ $axcientName" }
        })
    }

    foreach ($company in @($HuduCompanies | Sort-Object name, id)) {
        $id = Get-AmdMatchingId $company.id
        if ($null -eq $id) { continue }
        if ($usedHudu.Contains($id)) { continue }
        $rows.Add([pscustomobject]@{
            Kind           = 'HuduOnly'
            HuduName       = [string]$company.name
            HuduId         = $id
            HuduExists     = $true
            HuduDisplay    = "$($company.name) (ID $id)"
            AxcientName    = ''
            AxcientId      = $null
            AxcientExists  = $false
            AxcientDisplay = '—'
            MatchedDisplay = '✕ Not matched'
            MatchColor     = '#E5544B'
            Connection     = 'Not connected'
        })
    }

    foreach ($client in @($AxcientClients | Sort-Object name, id)) {
        $id = Get-AmdMatchingId $client.id
        if ($null -eq $id) { continue }
        if ($usedAxcient.Contains($id)) { continue }
        $rows.Add([pscustomobject]@{
            Kind           = 'AxcientOnly'
            HuduName       = ''
            HuduId         = $null
            HuduExists     = $false
            HuduDisplay    = '—'
            AxcientName    = [string]$client.name
            AxcientId      = $id
            AxcientExists  = $true
            AxcientDisplay = "$($client.name) (ID $id)"
            MatchedDisplay = '✕ Not matched'
            MatchColor     = '#E5544B'
            Connection     = 'Not connected'
        })
    }

    return @($rows)
}

function Get-AmdMatchingSelectionState {
    [CmdletBinding()]
    param([AllowNull()][object[]]$SelectedRows = @())

    $selected = @($SelectedRows)
    $huduOnlyCount = @($selected | Where-Object Kind -eq 'HuduOnly').Count
    $axcientOnlyCount = @($selected | Where-Object Kind -eq 'AxcientOnly').Count
    $matchedCount = @($selected | Where-Object Kind -in 'Matched', 'Stale').Count

    return [pscustomobject]@{
        CanManualMatch = $selected.Count -eq 2 -and $huduOnlyCount -eq 1 -and $axcientOnlyCount -eq 1
        CanUnmatch     = $selected.Count -eq 1 -and $matchedCount -eq 1
    }
}

function Show-AmdUnmatchDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$MatchRow,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AvailableHuduCompanies
    )

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Unmatch company" Width="610" Height="390" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#0E1017" Foreground="#F4F6FB" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="Background" Value="#6136FF"/>
      <Setter Property="Padding" Value="16,9"/><Setter Property="Margin" Value="5"/>
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Margin" Value="5"/><Setter Property="Padding" Value="8"/>
      <Setter Property="Background" Value="#12151D"/><Setter Property="Foreground" Value="#F4F6FB"/>
      <Setter Property="BorderBrush" Value="#3A4152"/>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#1C2029"/><Setter Property="Foreground" Value="#F4F6FB"/>
      <Setter Property="Padding" Value="8"/>
    </Style>
  </Window.Resources>
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Unmatch this connection?" FontSize="22" FontWeight="SemiBold"/>
    <TextBlock x:Name="ConnectionText" Grid.Row="1" Margin="0,12,0,10" Foreground="#B7A4FF" TextWrapping="Wrap"/>
    <TextBlock Grid.Row="2" Foreground="#A3AABD" TextWrapping="Wrap"
               Text="Delete removes only the managed Magic Dash from the old company. Move queues it for another Hudu company. The console performs these changes only after you click OK in the main window."/>
    <StackPanel Grid.Row="3" Margin="0,16,0,0">
      <TextBlock Text="Move destination" FontWeight="SemiBold"/>
      <ComboBox x:Name="TargetCompany" DisplayMemberPath="Display"/>
      <TextBlock Text="AXCIENT-MAGIC-DASH recreates the managed Magic Dash in the selected company, then removes it from the old company." Foreground="#E0A44F" TextWrapping="Wrap" Margin="5,8,5,0"/>
    </StackPanel>
    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="DeleteButton" Content="Delete old Magic Dash" Background="#E5544B"/>
      <Button x:Name="MoveButton" Content="Move to selected company"/>
      <Button x:Name="CancelButton" Content="Cancel" Background="#212632"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.FindName('ConnectionText').Text = $MatchRow.Connection
    $target = $window.FindName('TargetCompany')
    $target.ItemsSource = @(
        $AvailableHuduCompanies |
            Sort-Object name, id |
            ForEach-Object {
                $companyId = Get-AmdMatchingId $_.id
                if ($null -ne $companyId -and $companyId -ne [int64]$MatchRow.HuduId) {
                    [pscustomobject]@{ Id = $companyId; Name = [string]$_.name; Display = "$($_.name) (ID $companyId)" }
                }
            }
    )
    $window.FindName('MoveButton').IsEnabled = @($target.ItemsSource).Count -gt 0

    $result = [pscustomobject]@{ Action = 'Cancel'; TargetHuduId = $null; TargetHuduName = $null }
    $window.FindName('DeleteButton').Add_Click({
        $result.Action = 'Delete'
        $window.DialogResult = $true
        $window.Close()
    })
    $window.FindName('MoveButton').Add_Click({
        if ($null -eq $target.SelectedItem) {
            [System.Windows.MessageBox]::Show('Select the destination Hudu company first.', 'Destination required', 'OK', 'Warning') | Out-Null
            return
        }
        $result.Action = 'Move'
        $result.TargetHuduId = [int64]$target.SelectedItem.Id
        $result.TargetHuduName = [string]$target.SelectedItem.Name
        $window.DialogResult = $true
        $window.Close()
    })
    $window.FindName('CancelButton').Add_Click({ $window.Close() })
    $null = $window.ShowDialog()
    return $result
}

function Show-AmdMatchingWindow {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$HuduCompanies = @(),
        [AllowNull()][object[]]$AxcientClients = @(),
        [Alias('Matches')]
        [AllowNull()][object[]]$ExistingMatches = @()
    )

    if (-not $IsWindows) {
        throw 'The matching window requires Windows.'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw 'The matching window requires an STA PowerShell session. Start run.ps1 normally; it relaunches the menu in STA mode when needed.'
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (@($HuduCompanies).Count -eq 0 -or @($AxcientClients).Count -eq 0) {
        $missing = if (@($HuduCompanies).Count -eq 0 -and @($AxcientClients).Count -eq 0) {
            'No Hudu companies or Axcient clients were returned.'
        }
        elseif (@($HuduCompanies).Count -eq 0) { 'No Hudu companies were returned.' }
        else { 'No Axcient clients were returned.' }
        [System.Windows.MessageBox]::Show("$missing Existing stale matches are still shown so they can be removed or repaired.", 'Endpoint list is empty', 'OK', 'Information') | Out-Null
    }

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AXCIENT-MAGIC-DASH — Company Matching" Width="1220" Height="720"
        MinWidth="900" MinHeight="520" WindowStartupLocation="CenterScreen"
        Background="#0E1017" Foreground="#F4F6FB" FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/><Setter Property="Background" Value="#6136FF"/>
      <Setter Property="Padding" Value="18,10"/><Setter Property="Margin" Value="5"/>
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="#181B24"/><Setter Property="Foreground" Value="#F4F6FB"/>
      <Setter Property="RowBackground" Value="#181B24"/><Setter Property="AlternatingRowBackground" Value="#212632"/>
      <Setter Property="BorderBrush" Value="#2A2F3B"/><Setter Property="GridLinesVisibility" Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#2A2F3B"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#212632"/><Setter Property="Foreground" Value="#F4F6FB"/>
      <Setter Property="Padding" Value="10"/><Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="9,6"/>
      <Setter Property="Foreground" Value="#F4F6FB"/>
    </Style>
  </Window.Resources>
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Company matching" FontSize="26" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" Margin="0,6,0,14" Foreground="#A3AABD" TextWrapping="Wrap"
               Text="Green exact-name matches are already staged—click OK to save them and run the sync. To create a different manual match, Ctrl+click one Hudu-only row and one Axcient-only row. To change a saved match later, select it and click Unmatch. IDs keep duplicate names unambiguous."/>
    <DataGrid x:Name="MatchGrid" Grid.Row="2" AutoGenerateColumns="False" IsReadOnly="True"
              SelectionMode="Extended" SelectionUnit="FullRow" AlternationCount="2">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Hudu company / ID" Binding="{Binding HuduDisplay}" Width="1.15*"/>
        <DataGridTextColumn Header="Axcient client / ID" Binding="{Binding AxcientDisplay}" Width="1.15*"/>
        <DataGridTemplateColumn Header="Matched" Width="0.65*">
          <DataGridTemplateColumn.CellTemplate>
            <DataTemplate><TextBlock Text="{Binding MatchedDisplay}" Foreground="{Binding MatchColor}" FontWeight="SemiBold"/></DataTemplate>
          </DataGridTemplateColumn.CellTemplate>
        </DataGridTemplateColumn>
        <DataGridTextColumn Header="Connection" Binding="{Binding Connection}" Width="1.45*"/>
      </DataGrid.Columns>
    </DataGrid>
    <TextBlock x:Name="StatusText" Grid.Row="3" Margin="4,10,4,4" Foreground="#A3AABD"/>
    <DockPanel Grid.Row="4">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
        <Button x:Name="MatchButton" Content="Manually match selected" IsEnabled="False"/>
        <Button x:Name="UnmatchButton" Content="Unmatch selected" Background="#E5544B" IsEnabled="False"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="CancelButton" Content="Cancel" Background="#212632"/>
        <Button x:Name="OkButton" Content="OK — apply changes"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $grid = $window.FindName('MatchGrid')
    $status = $window.FindName('StatusText')
    $matchButton = $window.FindName('MatchButton')
    $unmatchButton = $window.FindName('UnmatchButton')
    $workingMatches = [System.Collections.Generic.List[object]]::new()
    foreach ($match in @($ExistingMatches)) { if ($null -ne $match) { $workingMatches.Add($match) } }
    $operations = [System.Collections.Generic.List[object]]::new()
    $dialogState = [pscustomobject]@{ Accepted = $false }

    $updateButtonState = {
        $selectionState = Get-AmdMatchingSelectionState -SelectedRows @($grid.SelectedItems)
        $matchButton.IsEnabled = $selectionState.CanManualMatch
        $unmatchButton.IsEnabled = $selectionState.CanUnmatch
    }

    $refresh = {
        $rows = @(New-AmdMatchRows -HuduCompanies $HuduCompanies -AxcientClients $AxcientClients -ExistingMatches @($workingMatches))
        $grid.ItemsSource = $rows
        $staleCount = @($rows | Where-Object Kind -eq 'Stale').Count
        $matchedCount = @($rows | Where-Object Kind -eq 'Matched').Count
        $status.Text = "$matchedCount active match(es); $staleCount stale match(es); $($operations.Count) queued cleanup/move operation(s)."
        & $updateButtonState
    }

    $grid.Add_SelectionChanged({ & $updateButtonState })

    $window.FindName('MatchButton').Add_Click({
        $selected = @($grid.SelectedItems)
        $huduRows = @($selected | Where-Object Kind -eq 'HuduOnly')
        $axcientRows = @($selected | Where-Object Kind -eq 'AxcientOnly')
        if ($selected.Count -ne 2 -or $huduRows.Count -ne 1 -or $axcientRows.Count -ne 1) {
            [System.Windows.MessageBox]::Show('Select exactly one Hudu-only row and one Axcient-only row. Hold Ctrl while selecting the second row.', 'Select one from each side', 'OK', 'Warning') | Out-Null
            return
        }
        $queuedForCompany = @($operations | Where-Object { [int64]$_.SourceHuduId -eq [int64]$huduRows[0].HuduId })
        if ($queuedForCompany.Count -gt 0) {
            $restoresDeletedMatch =
                $queuedForCompany.Count -eq 1 -and
                $queuedForCompany[0].Action -eq 'Delete' -and
                [int64]$queuedForCompany[0].AxcientId -eq [int64]$axcientRows[0].AxcientId
            if ($restoresDeletedMatch) {
                $null = $operations.Remove($queuedForCompany[0])
            }
            else {
                [System.Windows.MessageBox]::Show('That Hudu company has a queued delete or move operation. Apply the queued operation first; it cannot be reused for another client in the same session.', 'Company cleanup is pending', 'OK', 'Warning') | Out-Null
                return
            }
        }
        $workingMatches.Add([pscustomobject]@{
            name      = [string]$axcientRows[0].AxcientName
            axcientId = [int64]$axcientRows[0].AxcientId
            huduID    = [int64]$huduRows[0].HuduId
        })
        & $refresh
    })

    $window.FindName('UnmatchButton').Add_Click({
        $selected = @($grid.SelectedItems)
        if ($selected.Count -ne 1 -or $selected[0].Kind -notin 'Matched', 'Stale') {
            [System.Windows.MessageBox]::Show('Select exactly one matched or stale row to unmatch.', 'Select one match', 'OK', 'Warning') | Out-Null
            return
        }
        $row = $selected[0]
        if (@($operations | Where-Object { [int64]$_.AxcientId -eq [int64]$row.AxcientId }).Count -gt 0) {
            [System.Windows.MessageBox]::Show('This Axcient client already has a queued move/delete operation in this session. Click Cancel and reopen matching if you need to choose a different operation.', 'One queued operation per client', 'OK', 'Warning') | Out-Null
            return
        }
        $decision = Show-AmdUnmatchDialog -MatchRow $row -AvailableHuduCompanies $HuduCompanies
        if ($decision.Action -eq 'Cancel') { return }

        if ($decision.Action -eq 'Move') {
            if (-not $row.AxcientExists) {
                [System.Windows.MessageBox]::Show('This Axcient client no longer exists, so there is no live backup data to move. Choose Delete old content to remove the stale match.', 'Missing Axcient client', 'OK', 'Warning') | Out-Null
                return
            }
            $targetAlreadyUsed = @($workingMatches | Where-Object { [int64]$_.huduID -eq [int64]$decision.TargetHuduId }).Count -gt 0
            if ($targetAlreadyUsed) {
                [System.Windows.MessageBox]::Show('That Hudu company is already matched to an Axcient client. Unmatch it first or choose another company.', 'Destination already connected', 'OK', 'Warning') | Out-Null
                return
            }
            if (@($operations | Where-Object { [int64]$_.SourceHuduId -eq [int64]$decision.TargetHuduId }).Count -gt 0) {
                [System.Windows.MessageBox]::Show('That Hudu company was freed by another queued operation in this session. Apply the current changes first, then reopen matching before targeting it. This prevents dependent moves from becoming inconsistent if an earlier operation fails.', 'Apply queued move first', 'OK', 'Warning') | Out-Null
                return
            }
            $targetCompany = @($HuduCompanies | Where-Object {
                    $candidateId = Get-AmdMatchingId $_.id
                    $null -ne $candidateId -and $candidateId -eq [int64]$decision.TargetHuduId
                })
            # The count is checked first: indexing element 0 of an empty result is
            # only survivable while strict mode is off.
            $sameNameCount = if ($targetCompany.Count -eq 1) {
                @($HuduCompanies | Where-Object {
                    [string]::Equals([string]$_.name, [string]$targetCompany[0].name, [StringComparison]::OrdinalIgnoreCase)
                }).Count
            }
            else { 0 }
            if ($targetCompany.Count -ne 1 -or $sameNameCount -ne 1) {
                [System.Windows.MessageBox]::Show("That Hudu company name is duplicated. Hudu's Magic Dash API targets company names, so the move is blocked to avoid writing to the wrong company. Rename the duplicate companies in Hudu first.", 'Unique Hudu name required', 'OK', 'Warning') | Out-Null
                return
            }
        }

        $existing = @($workingMatches | Where-Object {
            [int64]$_.huduID -eq [int64]$row.HuduId -and [int64]$_.axcientId -eq [int64]$row.AxcientId
        })
        foreach ($item in $existing) { $null = $workingMatches.Remove($item) }

        $operations.Add([pscustomobject]@{
            Action          = [string]$decision.Action
            SourceHuduId    = [int64]$row.HuduId
            SourceHuduName  = [string]$row.HuduName
            SourceHuduExists = [bool]$row.HuduExists
            TargetHuduId    = $decision.TargetHuduId
            TargetHuduName  = $decision.TargetHuduName
            AxcientId       = [int64]$row.AxcientId
            AxcientName     = [string]$row.AxcientName
        })
        if ($decision.Action -eq 'Move') {
            $workingMatches.Add([pscustomobject]@{
                name      = [string]$row.AxcientName
                axcientId = [int64]$row.AxcientId
                huduID    = [int64]$decision.TargetHuduId
            })
        }
        & $refresh
    })

    $window.FindName('OkButton').Add_Click({
        $dialogState.Accepted = $true
        $window.DialogResult = $true
        $window.Close()
    })
    $window.FindName('CancelButton').Add_Click({ $window.Close() })
    $window.Add_Closing({
        if (-not $dialogState.Accepted) { $dialogState.Accepted = $false }
    })

    & $refresh
    $null = $window.ShowDialog()
    return [pscustomobject]@{
        Cancelled  = -not $dialogState.Accepted
        Matches    = if ($dialogState.Accepted) { @($workingMatches) } else { @($ExistingMatches) }
        Operations = if ($dialogState.Accepted) { @($operations) } else { @() }
    }
}

function Resolve-AmdMissingMoveDestinations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][scriptblock]$ReadConfirmation
    )

    $pending = @($Config.pendingOperations)
    if ($pending.Count -eq 0) { return $false }
    $companies = [System.Collections.Generic.List[object]]::new()
    foreach ($company in @(Get-AmdHuduCompany -ErrorAction Stop)) {
        if ($null -eq (Get-AmdMatchingId $company.id)) {
            Write-Warning "Hudu returned company '$($company.name)' with an invalid ID. It was excluded from move recovery." -WarningAction Continue
            continue
        }
        $companies.Add($company)
    }
    $changed = $false
    $remaining = [System.Collections.Generic.List[object]]::new()

    foreach ($operation in $pending) {
        $targetMatches = if ($operation.Action -eq 'Move') {
            @($companies | Where-Object { (Get-AmdMatchingId $_.id) -eq [int64]$operation.TargetHuduId })
        }
        else { @() }
        if ($operation.Action -ne 'Move' -or $targetMatches.Count -gt 0) {
            $remaining.Add($operation)
            continue
        }

        Write-Host "The saved move destination '$($operation.TargetHuduName)' (Hudu ID $($operation.TargetHuduId)) no longer exists." -ForegroundColor Red
        if (-not (& $ReadConfirmation "Abandon this impossible move for '$($operation.AxcientName)'?")) {
            $remaining.Add($operation)
            continue
        }

        $Config.matches = @($Config.matches | Where-Object { [int64]$_.axcientId -ne [int64]$operation.AxcientId })
        $source = @($companies | Where-Object { (Get-AmdMatchingId $_.id) -eq [int64]$operation.SourceHuduId })
        $sourceAlreadyMatched = @($Config.matches | Where-Object { [int64]$_.huduID -eq [int64]$operation.SourceHuduId }).Count -gt 0
        if ($source.Count -eq 1 -and -not $sourceAlreadyMatched) {
            $Config.matches = @($Config.matches) + [pscustomobject]@{
                name      = [string]$operation.AxcientName
                axcientId = [int64]$operation.AxcientId
                huduID    = [int64]$source[0].id
            }
            Write-Host "Restored the match to '$($source[0].name)'. Source content was retained by the move safety rules." -ForegroundColor Green
        }
        elseif ($sourceAlreadyMatched) {
            Write-Host 'The original company is now matched to another Axcient client, so the abandoned client was left unmatched.' -ForegroundColor Yellow
        }
        else {
            Write-Host 'The original company is also unavailable, so the Axcient client was left unmatched.' -ForegroundColor Yellow
        }
        $changed = $true
    }

    if ($changed) {
        $Config.pendingOperations = @($remaining)
        Save-AmdConfig -Config $Config -Path $ConfigPath | Out-Null
    }
    return $changed
}
