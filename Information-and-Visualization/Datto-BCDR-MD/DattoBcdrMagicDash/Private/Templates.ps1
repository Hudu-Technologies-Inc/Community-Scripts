# Every rule is scoped beneath the unique .datto-magic-dash root class so this
# stylesheet can never restyle unrelated Hudu content. The markup also keeps
# Hudu's own nasa__/basic_info__ class names so the dashboard still reads
# correctly if a Hudu build strips embedded <style> elements.
$script:DbmScopedStyle = @'
<style>
.datto-magic-dash{--dbm-primary:#6136FF;--dbm-primary-dark:#4B21D6;--dbm-ink:#1F2430;--dbm-muted:#59617A;--dbm-border:#E1E4EF;--dbm-surface:#FFFFFF;--dbm-shell:#F7F7FC;--dbm-ok-bg:#E4F5EA;--dbm-ok-ink:#14663A;--dbm-warn-bg:#FDE8E6;--dbm-warn-ink:#992017;box-sizing:border-box;container-type:inline-size;color:var(--dbm-ink);font-size:14px;line-height:1.45;max-width:100%;overflow-wrap:break-word}
.datto-magic-dash *,.datto-magic-dash *::before,.datto-magic-dash *::after{box-sizing:inherit}
.datto-magic-dash .nasa__content{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;align-items:stretch;margin:0 0 16px;padding:0;width:100%;max-width:100%}
.datto-magic-dash .dbm-dashboard-column{display:flex;flex-direction:column;gap:16px;min-width:0;max-width:100%}
.datto-magic-dash .nasa__block{height:auto;min-width:0;max-width:100%;margin:0 0 16px;padding:14px 16px;border:1px solid var(--dbm-border);border-radius:10px;background:var(--dbm-surface);overflow:hidden}
.datto-magic-dash .nasa__content .nasa__block{margin:0}
.datto-magic-dash .dbm-device-panel{display:flex;flex-direction:column;min-width:0;max-width:100%}
.datto-magic-dash .dbm-server-panel{flex:1 1 240px;min-height:240px}
.datto-magic-dash .nasa__block-header{display:block;margin:0 0 12px;padding:0 0 8px;border-bottom:2px solid var(--dbm-primary)}
.datto-magic-dash .nasa__block-header h1{display:flex;align-items:center;gap:8px;min-width:0;max-width:100%;overflow:hidden;margin:0;padding:0;font-size:1.05em;font-weight:700;line-height:1.3;color:#FFFFFF;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .nasa__block-header h1 i{display:inline-block;flex:0 0 auto;font-style:normal}
.datto-magic-dash .dbm-subhead{margin:18px 0 8px;padding:0 0 6px;border-bottom:1px solid var(--dbm-border);font-size:.95em;font-weight:700;color:var(--dbm-primary-dark)}
.datto-magic-dash .dbm-actions{margin:0 0 12px}
.datto-magic-dash a.dbm-button{display:inline-block;max-width:100%;padding:8px 14px;border:0;border-radius:6px;background:var(--dbm-primary);color:#FFFFFF;font-weight:600;text-decoration:none;overflow-wrap:anywhere}
.datto-magic-dash a.dbm-button:hover,.datto-magic-dash a.dbm-button:focus{background:var(--dbm-primary-dark);color:#FFFFFF;text-decoration:none}
.datto-magic-dash a.dbm-button:focus-visible{outline:2px solid var(--dbm-primary-dark);outline-offset:2px}
.datto-magic-dash .dbm-facts{display:grid;grid-template-columns:1fr;gap:0;margin:0}
.datto-magic-dash .basic_info__section{display:grid;grid-template-columns:minmax(110px,32%) 1fr;gap:4px 14px;align-items:baseline;margin:0;padding:8px 0;border-bottom:1px solid var(--dbm-border)}
.datto-magic-dash .basic_info__section:last-child{border-bottom:0}
.datto-magic-dash .basic_info__section h2{margin:0;padding:0;min-width:0;max-width:100%;overflow:hidden;font-size:.9em;font-weight:600;line-height:1.45;color:var(--dbm-muted);white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .basic_info__section p{margin:0;padding:0;min-width:0;max-width:100%;overflow:hidden;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-note{display:block;color:var(--dbm-muted);font-size:.85em}
.datto-magic-dash .dbm-summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(100px,1fr));gap:8px;margin:0 0 12px}
.datto-magic-dash .dbm-metric{min-width:0;max-width:100%;overflow:hidden;padding:10px;border:1px solid var(--dbm-border);border-radius:8px;background:var(--dbm-shell);text-align:center;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-metric span{display:block;color:var(--dbm-muted);font-size:.82em;font-weight:600}
.datto-magic-dash .dbm-metric strong{display:block;max-width:100%;overflow:hidden;margin-top:2px;font-size:1.25em;font-variant-numeric:tabular-nums;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-table-wrap{width:100%;max-width:100%;overflow-x:auto;overflow-y:hidden;-webkit-overflow-scrolling:touch}
.datto-magic-dash table{width:100%;margin:0;border-collapse:collapse;table-layout:fixed;font-size:.92em;background:transparent;box-shadow:none}
.datto-magic-dash .dbm-table--appliances{min-width:460px}
.datto-magic-dash .dbm-table--counts{min-width:360px}
.datto-magic-dash .dbm-table--restores{min-width:420px}
.datto-magic-dash .dbm-table--alerts{min-width:460px}
.datto-magic-dash thead th{max-width:100%;overflow:hidden;padding:8px 10px;border-bottom:2px solid var(--dbm-border);background:var(--dbm-shell);color:var(--dbm-muted);font-weight:700;text-align:left;vertical-align:bottom;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash tbody th,.datto-magic-dash tbody td{max-width:100%;overflow:hidden;padding:8px 10px;border-bottom:1px solid var(--dbm-border);text-align:left;vertical-align:top;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash tbody th{font-weight:600;color:var(--dbm-ink)}
.datto-magic-dash tbody tr:last-child th,.datto-magic-dash tbody tr:last-child td{border-bottom:0}
.datto-magic-dash .dbm-table--counts tbody th,.datto-magic-dash .dbm-table--counts tbody td{background:#FFFFFF!important;color:#1F2430!important}
.datto-magic-dash .dbm-num{text-align:right;font-variant-numeric:tabular-nums}
.datto-magic-dash .dbm-device-scroll{width:100%;max-width:100%;max-height:520px;min-height:0;overflow:auto;overscroll-behavior:contain;scrollbar-gutter:stable;-webkit-overflow-scrolling:touch;border:1px solid var(--dbm-border);border-radius:8px;background:var(--dbm-surface)}
.datto-magic-dash .dbm-server-panel>.dbm-device-scroll{flex:1 1 auto;min-height:140px;max-height:280px}
.datto-magic-dash .dbm-device-list{width:100%;min-width:0;max-width:100%}
.datto-magic-dash .dbm-device-grid{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(0,1fr) minmax(0,.8fr) minmax(0,.95fr) minmax(0,1.25fr) minmax(0,1fr) minmax(0,.95fr);width:100%;min-width:0;max-width:100%}
.datto-magic-dash .dbm-device-head{position:sticky;top:0;z-index:2;background:var(--dbm-shell);color:var(--dbm-muted);font-size:.82em;font-weight:700;text-transform:uppercase}
.datto-magic-dash .dbm-device-head>div{min-width:0;max-width:100%;overflow:hidden;padding:8px 10px;border-bottom:2px solid var(--dbm-border);white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-device-row{align-items:start;border-bottom:1px solid var(--dbm-border);background:var(--dbm-surface)}
.datto-magic-dash .dbm-device-row:last-child{border-bottom:0}
.datto-magic-dash .dbm-device-row.dbm-row--warn{background:var(--dbm-warn-bg)}
.datto-magic-dash .dbm-device-cell{min-width:0;max-width:100%;overflow:hidden;padding:9px 10px;text-align:left;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-device-cell *{max-width:100%;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-device-cell::before{display:none;margin:0 0 3px;color:var(--dbm-muted);font-size:.78em;font-weight:700;line-height:1.2;text-transform:uppercase}
.datto-magic-dash .dbm-device-cell:nth-child(1)::before{content:"Device"}
.datto-magic-dash .dbm-device-cell:nth-child(2)::before{content:"System"}
.datto-magic-dash .dbm-device-cell:nth-child(3)::before{content:"Agent"}
.datto-magic-dash .dbm-device-cell:nth-child(4)::before{content:"Health"}
.datto-magic-dash .dbm-device-cell:nth-child(5)::before{content:"Recovery points"}
.datto-magic-dash .dbm-device-cell:nth-child(6)::before{content:"Volumes"}
.datto-magic-dash .dbm-device-cell:nth-child(7)::before{content:"Screenshot"}
.datto-magic-dash .dbm-server-panel .dbm-device-head{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.datto-magic-dash .dbm-server-panel .dbm-device-row{grid-template-columns:repeat(2,minmax(0,1fr));margin:0;padding:4px}
.datto-magic-dash .dbm-server-panel .dbm-device-cell{padding:7px 8px}
.datto-magic-dash .dbm-server-panel .dbm-device-cell::before{display:block}
.datto-magic-dash .dbm-badge{display:inline-block;max-width:100%;padding:2px 10px;border-radius:999px;font-size:.85em;font-weight:700;line-height:1.6;white-space:normal;overflow-wrap:anywhere}
.datto-magic-dash .dbm-badge--ok{background:var(--dbm-ok-bg);color:var(--dbm-ok-ink)}
.datto-magic-dash .dbm-badge--warn{background:var(--dbm-warn-bg);color:var(--dbm-warn-ink)}
.datto-magic-dash .dbm-reason{display:block;margin-top:3px;color:var(--dbm-muted);font-size:.9em;overflow-wrap:anywhere}
.datto-magic-dash .dbm-rp{display:block;margin:0 0 4px}
.datto-magic-dash .dbm-links{display:flex;flex-wrap:wrap;gap:6px}
.datto-magic-dash a.dbm-chip{display:inline-block;padding:3px 10px;border:1px solid var(--dbm-primary);border-radius:999px;background:var(--dbm-surface);color:var(--dbm-primary-dark);font-size:.85em;font-weight:600;text-decoration:none;white-space:nowrap}
.datto-magic-dash a.dbm-chip:hover,.datto-magic-dash a.dbm-chip:focus{background:var(--dbm-primary);color:#FFFFFF;text-decoration:none}
.datto-magic-dash a.dbm-chip:focus-visible{outline:2px solid var(--dbm-primary-dark);outline-offset:2px}
.datto-magic-dash .dbm-table--appliances a.dbm-chip{white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-chip--muted{border-color:var(--dbm-border);color:var(--dbm-muted);font-weight:600}
.datto-magic-dash .dbm-empty{max-width:100%;overflow:hidden;margin:0;padding:16px;border:1px dashed var(--dbm-border);border-radius:8px;background:var(--dbm-shell);color:var(--dbm-muted);text-align:center;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.datto-magic-dash .dbm-warning-summary{border-color:var(--dbm-warn-ink);background:var(--dbm-warn-bg);color:var(--dbm-warn-ink)}
.datto-magic-dash details.mce-accordion{margin:0 0 8px;padding:8px 10px;border:1px solid var(--dbm-border);border-radius:8px;background:var(--dbm-surface)}
.datto-magic-dash details.mce-accordion>summary{cursor:pointer;font-weight:600;overflow-wrap:anywhere}
.datto-magic-dash details.mce-accordion p{margin:6px 0 0;overflow-wrap:anywhere}
@media (max-width:900px){
.datto-magic-dash .nasa__content{grid-template-columns:1fr}
.datto-magic-dash .dbm-server-panel>.dbm-device-scroll{max-height:360px}
}
@media (max-width:1100px){
.datto-magic-dash .dbm-workstation-panel .dbm-device-head,.datto-magic-dash .dbm-other-device-panel .dbm-device-head{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.datto-magic-dash .dbm-workstation-panel .dbm-device-row,.datto-magic-dash .dbm-other-device-panel .dbm-device-row{grid-template-columns:repeat(2,minmax(0,1fr));margin:0;padding:4px}
.datto-magic-dash .dbm-workstation-panel .dbm-device-cell,.datto-magic-dash .dbm-other-device-panel .dbm-device-cell{padding:7px 8px}
.datto-magic-dash .dbm-workstation-panel .dbm-device-cell::before,.datto-magic-dash .dbm-other-device-panel .dbm-device-cell::before{display:block}
}
@media (max-width:640px){
.datto-magic-dash{font-size:13px}
.datto-magic-dash .nasa__block{padding:12px}
.datto-magic-dash .basic_info__section{grid-template-columns:1fr;gap:2px}
.datto-magic-dash .dbm-device-row,.datto-magic-dash .dbm-server-panel .dbm-device-row,.datto-magic-dash .dbm-workstation-panel .dbm-device-row,.datto-magic-dash .dbm-other-device-panel .dbm-device-row{grid-template-columns:1fr}
.datto-magic-dash a.dbm-button{display:block;text-align:center}
}
@container (max-width:900px){
.datto-magic-dash .nasa__content{grid-template-columns:1fr}
.datto-magic-dash .dbm-server-panel>.dbm-device-scroll{max-height:360px}
}
@container (max-width:1100px){
.datto-magic-dash .dbm-workstation-panel .dbm-device-head,.datto-magic-dash .dbm-other-device-panel .dbm-device-head{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.datto-magic-dash .dbm-workstation-panel .dbm-device-row,.datto-magic-dash .dbm-other-device-panel .dbm-device-row{grid-template-columns:repeat(2,minmax(0,1fr));margin:0;padding:4px}
.datto-magic-dash .dbm-workstation-panel .dbm-device-cell,.datto-magic-dash .dbm-other-device-panel .dbm-device-cell{padding:7px 8px}
.datto-magic-dash .dbm-workstation-panel .dbm-device-cell::before,.datto-magic-dash .dbm-other-device-panel .dbm-device-cell::before{display:block}
}
@container (max-width:640px){
.datto-magic-dash{font-size:13px}
.datto-magic-dash .nasa__block{padding:12px}
.datto-magic-dash .basic_info__section{grid-template-columns:1fr;gap:2px}
.datto-magic-dash .dbm-device-row,.datto-magic-dash .dbm-server-panel .dbm-device-row,.datto-magic-dash .dbm-workstation-panel .dbm-device-row,.datto-magic-dash .dbm-other-device-panel .dbm-device-row{grid-template-columns:1fr}
.datto-magic-dash a.dbm-button{display:block;text-align:center}
}
.datto-magic-dash article.dbm-device-card{margin:0;padding:14px 16px;border:1px solid var(--dbm-border);border-radius:10px;background:var(--dbm-surface)}
.datto-magic-dash article.dbm-device-card>header{margin:0 0 12px;padding:0 0 8px;border-bottom:2px solid var(--dbm-primary)}
.datto-magic-dash article.dbm-device-card>header h1{margin:0;padding:0;font-size:1.1em;font-weight:700;color:var(--dbm-ink);overflow-wrap:anywhere}
</style>
'@

$script:DbmMagicDashTemplate = '<div class="datto-magic-dash">' + $script:DbmScopedStyle + @'
<div class="nasa__content">
  <div class="dbm-dashboard-column dbm-dashboard-column--primary">
    <div class="nasa__block">
      <div class="nasa__block-header"><h1><i class="fas fa-info-circle icon"></i> Basic info</h1></div>
      <div class="dbm-basic-content">
        <p class="dbm-actions"><a class="button dbm-button" href="{{client_url}}" target="_blank" rel="noopener noreferrer">Open Datto portal</a></p>
        <article class="dbm-facts">
          <div class="basic_info__section"><h2>Client name</h2><p>{{name}}</p></div>
          <div class="basic_info__section"><h2>Health status</h2><p>{{health}}</p></div>
          <div class="basic_info__section"><h2>Hudu sync date</h2><p>{{last_update}}</p></div>
          <div class="basic_info__section"><h2>Time zone</h2><p>{{time_zone}} · <span class="dbm-note">Applies to all timestamps</span></p></div>
        </article>
      </div>
    </div>
    <div class="nasa__block dbm-device-panel dbm-server-panel">
      <div class="nasa__block-header"><h1><i class="fa-solid fa-server"></i> Servers</h1></div>
      {{server_devices}}
    </div>
  </div>
  <div class="dbm-dashboard-column dbm-dashboard-column--secondary">
    <div class="nasa__block">
      <div class="nasa__block-header"><h1><i class="fas fa-server icon"></i> Protected devices</h1></div>
      <div class="dbm-summary-grid">
        <div class="dbm-metric"><span>Healthy</span><strong>{{fleet_healthy}}</strong></div>
        <div class="dbm-metric"><span>Warning</span><strong>{{fleet_warning}}</strong></div>
        <div class="dbm-metric"><span>Screenshot verified</span><strong>{{fleet_screenshot}}</strong></div>
        <div class="dbm-metric"><span>Unknown</span><strong>{{fleet_unknown}}</strong></div>
      </div>
      <article class="dbm-facts">
        <div class="basic_info__section"><h2>Datto cloud storage</h2><p>{{cloud_storage}}</p></div>
        <div class="basic_info__section"><h2>Local appliance usage</h2><p>{{local_appliance_usage}}</p></div>
        <div class="basic_info__section"><h2>Stale backup threshold</h2><p>{{stale_threshold}} hour(s)</p></div>
      </article>
      <h2 class="dbm-subhead">Protection methods</h2>
      <div class="dbm-table-wrap">
        <table class="dbm-table--counts">
          <colgroup><col style="width:44%"><col style="width:28%"><col style="width:28%"></colgroup>
          <thead><tr><th scope="col">Protection</th><th scope="col" class="dbm-num">Servers</th><th scope="col" class="dbm-num">Workstations</th></tr></thead>
          <tbody>
            {{protection_rows}}

          </tbody>
        </table>
      </div>
      <h2 class="dbm-subhead">Appliances</h2>
      {{appliances}}
      <h2 class="dbm-subhead">Alert rules ({{alert_rule_count}})</h2>
      {{alert_rules}}
      <h2 class="dbm-subhead">VM restores ({{vm_restore_count}})</h2>
      {{vm_restores}}
    </div>
  </div>
</div>
{{warning_section}}
<div class="nasa__block dbm-device-panel dbm-workstation-panel">
  <div class="nasa__block-header"><h1><i class="fa-solid fa-desktop"></i> Workstations</h1></div>
  {{workstation_devices}}
</div>
{{other_device_section}}
</div>
'@

$script:DbmMagicDashWarningSectionTemplate = @'
<div class="nasa__block">
  <div class="nasa__block-header"><h1><i class="fa-solid fa-triangle-exclamation"></i> Warnings ({{warning_count}})</h1></div>
  <p class="dbm-empty dbm-warning-summary">{{warning_summary}}</p>
</div>
'@

$script:DbmMagicDashOtherDeviceSectionTemplate = @'
<div class="nasa__block dbm-device-panel dbm-other-device-panel">
  <div class="nasa__block-header"><h1><i class="fa-solid fa-circle-question"></i> Other devices</h1></div>
  {{other_devices}}
</div>
'@

$script:DbmDeviceCardOwnershipMarkerPrefix = '<!-- DATTO-BCDR-MAGIC-DASH:device:v1:'

$script:DbmDeviceCardTemplate = '<div class="datto-magic-dash">' + $script:DbmScopedStyle + @'
{{ownership_marker}}
<article class="dbm-device-card">
  <header>
    <h1>{{name}}</h1>
    <p class="dbm-note">{{type}} · {{protection_method}}</p>
  </header>
  <dl class="dbm-facts">
    <div class="basic_info__section"><h2>Datto device ID</h2><p>{{device_id}}</p></div>
    <div class="basic_info__section"><h2>Operating system</h2><p>{{operating_system}}</p></div>
    <div class="basic_info__section"><h2>IP address</h2><p>{{ip_address}}</p></div>
    <div class="basic_info__section"><h2>Agent version</h2><p>{{agent_version}}</p></div>
    <div class="basic_info__section"><h2>Health</h2><p>{{health}}</p></div>
    <div class="basic_info__section"><h2>Local recovery</h2><p>{{local_recovery}}</p></div>
    <div class="basic_info__section"><h2>Cloud recovery</h2><p>{{cloud_recovery}}</p></div>
    <div class="basic_info__section"><h2>Protected volumes</h2><p>{{protected_volumes}}</p></div>
    <div class="basic_info__section"><h2>Unprotected volumes</h2><p>{{unprotected_volumes}}</p></div>
    <div class="basic_info__section"><h2>Screenshot</h2><p>{{screenshot}}</p></div>
    <div class="basic_info__section"><h2>VM restores</h2><p>{{vm_restores}}</p></div>
  </dl>
  {{restore_detail}}
  <p class="dbm-actions"><a class="dbm-button" href="{{details_url}}" target="_blank" rel="noopener noreferrer">Open in Datto</a></p>
</article>
</div>
'@

function New-DbmDeviceCardHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$DeviceState,
        [Parameter(Mandatory)][int64]$DattoDeviceId
    )

    $health = New-DbmStatusBadge -Status $DeviceState.HealthStatus -Reason $DeviceState.HealthReason
    $stale = if ($DeviceState.IsStale) { ' <span class="dbm-badge dbm-badge--warn">Stale backup</span>' } else { '' }
    # Read through Get-DbmConfigProperty: a card can be rendered from a state
    # that never went through Add-DbmDeviceContext, and StrictMode makes a
    # missing property an error rather than an empty list.
    $deviceRestores = @(Get-DbmConfigProperty $DeviceState 'Restores' @())

    Merge-DbmTemplate -Template $script:DbmDeviceCardTemplate -Values @{
        ownership_marker   = "$($script:DbmDeviceCardOwnershipMarkerPrefix)$DattoDeviceId -->"
        name               = ConvertTo-DbmHtml $DeviceState.Name
        device_id          = ConvertTo-DbmHtml ([string]$DattoDeviceId)
        type               = ConvertTo-DbmHtml $DeviceState.Type
        protection_method  = ConvertTo-DbmHtml $DeviceState.ProtectionMethod
        operating_system   = ConvertTo-DbmHtml $DeviceState.OperatingSystem
        ip_address         = ConvertTo-DbmHtml $DeviceState.IpAddress
        agent_version      = ConvertTo-DbmHtml $DeviceState.AgentVersion
        health             = $health
        local_recovery     = (ConvertTo-DbmHtml $DeviceState.LocalRecoveryPoint.Display) + $stale
        cloud_recovery     = ConvertTo-DbmHtml $DeviceState.CloudRecoveryPoint.Display
        details_url        = ConvertTo-DbmSafeHref $DeviceState.DetailsUrl
        protected_volumes  = ConvertTo-DbmHtml (Get-DbmConfigProperty $DeviceState.Volumes 'ProtectedDetail' 'Not reported')
        unprotected_volumes = New-DbmVolumeCell -VolumeState $DeviceState.Volumes
        screenshot         = New-DbmScreenshotCell -DeviceState $DeviceState
        vm_restores        = if ($deviceRestores.Count -eq 0) {
            '<span class="dbm-note">None running</span>'
        }
        else {
            (New-DbmRestoreBadge -Restores $deviceRestores).TrimStart(' ', [char]0x00B7)
        }
        # The summary lines above answer "is anything wrong"; these tables answer
        # "what exactly", which is the question the asset is opened to settle.

        restore_detail     = if ($deviceRestores.Count -eq 0) {
            ''
        }
        else {
            '<h2 class="dbm-subhead">Running VM restores</h2>' + (New-DbmVmRestoreTable -Restores $deviceRestores -DataAvailable $true)
        }
    }
}
