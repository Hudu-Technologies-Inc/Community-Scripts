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
            IsPending     = $false
            PendingDisplay = ''
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
            IsPending     = $false
            PendingDisplay = ''
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
            IsPending     = $false
            PendingDisplay = ''
        })
    }

    return @($rows)
}

function New-AmdMatchingPendingSelection {
    <#
        .SYNOPSIS
        An empty click-to-match staging area.

        .DESCRIPTION
        Matching used to rely on modifier-key multi-select, which operators
        consistently got wrong: a plain second click silently replaced the
        first selection, so "Manually match selected" stayed disabled and the
        only clue was a greyed-out button.

        The pending selection replaces that. One left-click stages a row, a
        second left-click on the other side completes the pair, and the button
        enables. No modifier keys.

        HuduRow and AxcientRow are the two halves of a prospective match.
        MatchedRow is an existing match selected for unmatching. The two are
        mutually exclusive - you are either building a pair or acting on one.
    #>
    [CmdletBinding()]
    param()
    return [pscustomobject]@{ HuduRow = $null; AxcientRow = $null; MatchedRow = $null }
}

function Test-AmdMatchingSameRow {
    <#
        Whether two row objects are the same row.

        Compared by Kind plus BOTH ids rather than by reference, because the
        grid rebuilds its rows on every refresh: a reference comparison would
        quietly stop recognising the staged row the moment anything else
        changed, and the toggle would turn into "stage it again".
    #>
    [CmdletBinding()]
    param([AllowNull()]$First, [AllowNull()]$Second)

    if ($null -eq $First -or $null -eq $Second) { return $false }
    if ([string]$First.Kind -ne [string]$Second.Kind) { return $false }
    return ([string]$First.HuduId -eq [string]$Second.HuduId) -and
           ([string]$First.AxcientId -eq [string]$Second.AxcientId)
}

function Update-AmdMatchingPendingSelection {
    <#
        .SYNOPSIS
        The click-to-match state machine. No WPF, so it is directly testable.

        .DESCRIPTION
        One left-click, one transition:

            HuduOnly      stages (or unstages) the Hudu half, drops any
                          selected match
            AxcientOnly   stages (or unstages) the Axcient half, drops any
                          selected match
            Matched/Stale selects (or deselects) that match for unmatching,
                          and clears both halves of any part-built pair

        Clicking a DIFFERENT row on a side that is already staged REPLACES
        that side - the operator changed their mind about which company, and
        making them click twice to clear it first would be worse than useless.
        Clicking the SAME row again unstages it, which is the only way back to
        an empty selection without completing the match.

        Mutating and returning the same object keeps the caller's reference
        valid; the WPF handler holds exactly one of these for the window's
        lifetime.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Pending, [AllowNull()]$ClickedRow)

    if ($null -eq $Pending) { $Pending = New-AmdMatchingPendingSelection }
    # A click that lands on the header, the scrollbar or empty space below the
    # rows must not disturb a half-built pair.
    if ($null -eq $ClickedRow) { return $Pending }

    switch ([string]$ClickedRow.Kind) {
        'HuduOnly' {
            $Pending.MatchedRow = $null
            if (Test-AmdMatchingSameRow -First $Pending.HuduRow -Second $ClickedRow) { $Pending.HuduRow = $null }
            else { $Pending.HuduRow = $ClickedRow }
        }
        'AxcientOnly' {
            $Pending.MatchedRow = $null
            if (Test-AmdMatchingSameRow -First $Pending.AxcientRow -Second $ClickedRow) { $Pending.AxcientRow = $null }
            else { $Pending.AxcientRow = $ClickedRow }
        }
        default {
            # Matched and Stale both land here. Selecting an existing match is
            # a different intent from building a new one, so the part-built
            # pair goes - otherwise "Manually match" and "Unmatch" could both
            # be enabled and the window would be lying about what will happen.
            $Pending.HuduRow = $null
            $Pending.AxcientRow = $null
            if (Test-AmdMatchingSameRow -First $Pending.MatchedRow -Second $ClickedRow) { $Pending.MatchedRow = $null }
            else { $Pending.MatchedRow = $ClickedRow }
        }
    }

    return $Pending
}

function Update-AmdMatchRowPendingFlag {
    <#
        Stamps IsPending/PendingDisplay onto the rows so the grid can show
        what is staged.

        New-AmdMatchRows cannot do this itself - it builds the rows before
        anything has been clicked - so the flags are refreshed here on every
        transition. Returns nothing; the row objects are mutated in place and
        the caller calls Items.Refresh().
    #>
    [CmdletBinding()]
    param([AllowNull()][object[]]$Rows = @(), [AllowNull()]$Pending)

    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $isPending = $false
        $display = ''
        if ($null -ne $Pending) {
            if (Test-AmdMatchingSameRow -First $Pending.HuduRow -Second $row) { $isPending = $true; $display = '● Hudu' }
            elseif (Test-AmdMatchingSameRow -First $Pending.AxcientRow -Second $row) { $isPending = $true; $display = '● Axcient' }
            elseif (Test-AmdMatchingSameRow -First $Pending.MatchedRow -Second $row) { $isPending = $true; $display = '● Selected' }
        }
        $row.IsPending = $isPending
        $row.PendingDisplay = $display
    }
}

function Get-AmdMatchingSelectionState {
    <#
        What the two action buttons should be doing.

        Takes the pending selection rather than the grid's SelectedItems: with
        SelectionMode="Single" the grid can only ever report one row, so the
        old "exactly two selected, one from each side" test could never be
        true again.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Pending)

    return [pscustomobject]@{
        CanManualMatch = ($null -ne $Pending -and $null -ne $Pending.HuduRow -and $null -ne $Pending.AxcientRow)
        CanUnmatch     = ($null -ne $Pending -and $null -ne $Pending.MatchedRow)
    }
}
function Show-AmdUnmatchDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$MatchRow,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AvailableHuduCompanies,
        [AllowNull()][scriptblock]$AfterWindowLoaded
    )

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Unmatch company" Width="610" Height="390" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#0E1017" Foreground="#F4F6FB" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="#12151D"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="#F4F6FB"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#12151D"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#F4F6FB"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#3D5A80"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#2A3548"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#F4F6FB"/>
    <Style x:Key="AmdUnmatchComboItemStyle" TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#1C2029"/>
      <Setter Property="Foreground" Value="#F4F6FB"/>
      <Setter Property="Padding" Value="8,6"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
          <Setter Property="Background" Value="#3D5A80"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#2F4A6D"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
      </Style.Triggers>
    </Style>
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
      <Setter Property="Margin" Value="5"/><Setter Property="Padding" Value="8,6"/>
      <Setter Property="Background" Value="#12151D"/><Setter Property="Foreground" Value="#F4F6FB"/>
      <Setter Property="BorderBrush" Value="#3A4152"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource AmdUnmatchComboItemStyle}"/>
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

    if ($null -ne $AfterWindowLoaded) {
        $automationGate = [object[]]@(,$false)
        $window.Add_Loaded({
            if ($automationGate[0]) { return }
            $automationGate[0] = $true
            $null = $window.Dispatcher.BeginInvoke(
                [Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [action]{
                    & $AfterWindowLoaded @{
                        Window = $window
                        Combo  = $target
                    }
                }
            )
        })
    }

    $null = $window.ShowDialog()
    return $result
}

function Show-AmdMatchingWindow {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$HuduCompanies = @(),
        [AllowNull()][object[]]$AxcientClients = @(),
        [Alias('Matches')]
        [AllowNull()][object[]]$ExistingMatches = @(),
        # Optional hook for scripts/Invoke-LiveMatchingUiTest.ps1: runs once after the
        # grid is first rendered so QA can raise the same PreviewMouseLeftButtonDown
        # path the operator uses, then close with Cancel.
        [AllowNull()][scriptblock]$AfterWindowLoaded
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
               Text="Green exact-name matches are already staged—click OK to save them and run the sync. To create a different manual match, click one Hudu row, then click one Axcient row, then click Manually match selected. To change a saved match later, click it and click Unmatch. IDs keep duplicate names unambiguous."/>
    <DataGrid x:Name="MatchGrid" Grid.Row="2" AutoGenerateColumns="False" IsReadOnly="True"
              SelectionMode="Single" SelectionUnit="FullRow" AlternationCount="2">
      <DataGrid.RowStyle>
        <Style TargetType="DataGridRow">
          <Style.Triggers>
            <DataTrigger Binding="{Binding IsPending}" Value="True">
              <Setter Property="Background" Value="#2F4A6D"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </DataTrigger>
          </Style.Triggers>
        </Style>
      </DataGrid.RowStyle>
      <DataGrid.Columns>
        <DataGridTextColumn Header="Selected" Binding="{Binding PendingDisplay}" Width="0.5*"/>
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

    # One pending selection for the window's lifetime. The state machine
    # mutates it in place, so every closure below sees the same object.
    $pending = New-AmdMatchingPendingSelection

    $updateButtonState = {
        $selectionState = Get-AmdMatchingSelectionState -Pending $pending
        $matchButton.IsEnabled = $selectionState.CanManualMatch
        $unmatchButton.IsEnabled = $selectionState.CanUnmatch
    }

    $refresh = {
        # A match or unmatch has just been applied, so whatever was staged has
        # been consumed. Clearing the PROPERTIES rather than reassigning keeps
        # every closure pointed at the same object.
        $pending.HuduRow = $null
        $pending.AxcientRow = $null
        $pending.MatchedRow = $null
        $rows = @(New-AmdMatchRows -HuduCompanies $HuduCompanies -AxcientClients $AxcientClients -ExistingMatches @($workingMatches))
        Update-AmdMatchRowPendingFlag -Rows $rows -Pending $pending
        $grid.ItemsSource = $rows
        $staleCount = @($rows | Where-Object Kind -eq 'Stale').Count
        $matchedCount = @($rows | Where-Object Kind -eq 'Matched').Count
        $status.Text = "$matchedCount active match(es); $staleCount stale match(es); $($operations.Count) queued cleanup/move operation(s)."
        & $updateButtonState
    }

    # Left-click IS the gesture now. PreviewMouseLeftButtonDown fires before
    # the DataGrid does its own selection work, so the visual tree is walked
    # up from whatever was hit to find the owning row; a click on the header,
    # a scrollbar or the empty space below the last row finds nothing and is
    # deliberately left alone for the grid to handle normally.
    $grid.Add_PreviewMouseLeftButtonDown({
        # WPF hands this scriptblock (sender, RoutedEventArgs). They are taken
        # from $args rather than a param block on purpose: naming them trips
        # PSAvoidAssignmentToAutomaticVariable on $eventArgs and
        # PSReviewUnusedParameter on the unused sender, and a clean analyzer
        # run is a release gate for this project.
        $clickArgs = $args[1]
        $element = $clickArgs.OriginalSource -as [System.Windows.DependencyObject]
        while ($null -ne $element -and $element -isnot [System.Windows.Controls.DataGridRow]) {
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        }
        if ($null -eq $element) { return }
        $null = Update-AmdMatchingPendingSelection -Pending $pending -ClickedRow $element.Item
        Update-AmdMatchRowPendingFlag -Rows @($grid.ItemsSource) -Pending $pending
        $grid.Items.Refresh()
        & $updateButtonState
        # Handled, so the grid does not also apply its own selection on top of
        # the staging highlight - two different "selected" states on one row
        # is exactly the confusion this change exists to remove.
        $clickArgs.Handled = $true
    })

    $window.FindName('MatchButton').Add_Click({
        $huduRows = @($pending.HuduRow | Where-Object { $null -ne $_ })
        $axcientRows = @($pending.AxcientRow | Where-Object { $null -ne $_ })
        if ($huduRows.Count -ne 1 -or $axcientRows.Count -ne 1) {
            [System.Windows.MessageBox]::Show('Click one Hudu-only row and one Axcient-only row, then click Manually match selected.', 'Select one from each side', 'OK', 'Warning') | Out-Null
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
        $row = $pending.MatchedRow
        if ($null -eq $row -or [string]$row.Kind -notin 'Matched', 'Stale') {
            [System.Windows.MessageBox]::Show('Click exactly one matched or stale row to unmatch.', 'Select one match', 'OK', 'Warning') | Out-Null
            return
        }
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

    if ($null -ne $AfterWindowLoaded) {
        $automationGate = [object[]]@(,$false)
        $window.Add_Loaded({
            if ($automationGate[0]) { return }
            $automationGate[0] = $true
            $null = $window.Dispatcher.BeginInvoke(
                [Windows.Threading.DispatcherPriority]::ApplicationIdle,
                [action]{
                    & $AfterWindowLoaded @{
                        Window        = $window
                        Grid          = $grid
                        MatchButton   = $matchButton
                        UnmatchButton = $unmatchButton
                        StatusText    = $status
                        Pending       = $pending
                        Refresh       = $refresh
                    }
                }
            )
        })
    }

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
