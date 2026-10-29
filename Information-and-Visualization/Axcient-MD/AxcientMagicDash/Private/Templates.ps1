# Every rule is scoped beneath the unique .axcient-magic-dash root class so this
# stylesheet can never restyle unrelated Hudu content. The markup also keeps
# Hudu's own nasa__/basic_info__ class names so the dashboard still reads
# correctly if a Hudu build strips embedded <style> elements.
$script:AmdScopedStyle = @'
<style>
.axcient-magic-dash{--amd-primary:#6136FF;--amd-primary-dark:#4B21D6;--amd-ink:#1F2430;--amd-muted:#59617A;--amd-border:#E1E4EF;--amd-surface:#FFFFFF;--amd-shell:#F7F7FC;--amd-ok-bg:#E4F5EA;--amd-ok-ink:#14663A;--amd-warn-bg:#FDE8E6;--amd-warn-ink:#992017;box-sizing:border-box;container-type:inline-size;color:var(--amd-ink);font-size:14px;line-height:1.45;max-width:100%;overflow-wrap:break-word}
.axcient-magic-dash *,.axcient-magic-dash *::before,.axcient-magic-dash *::after{box-sizing:inherit}
.axcient-magic-dash .nasa__content{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;align-items:stretch;margin:0 0 16px;padding:0;width:100%;max-width:100%}
.axcient-magic-dash .amd-dashboard-column{display:flex;flex-direction:column;gap:16px;min-width:0;max-width:100%}
.axcient-magic-dash .nasa__block{height:auto;min-width:0;max-width:100%;margin:0 0 16px;padding:14px 16px;border:1px solid var(--amd-border);border-radius:10px;background:var(--amd-surface);overflow:hidden}
.axcient-magic-dash .nasa__content .nasa__block{margin:0}
.axcient-magic-dash .amd-device-panel{display:flex;flex-direction:column;min-width:0;max-width:100%}
.axcient-magic-dash .amd-server-panel{flex:1 1 240px;min-height:240px}
.axcient-magic-dash .nasa__block-header{display:block;margin:0 0 12px;padding:0 0 8px;border-bottom:2px solid var(--amd-primary)}
.axcient-magic-dash .nasa__block-header h1{display:flex;align-items:center;gap:8px;min-width:0;max-width:100%;overflow:hidden;margin:0;padding:0;font-size:1.05em;font-weight:700;line-height:1.3;color:#FFFFFF;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .nasa__block-header h1 i{display:inline-block;flex:0 0 auto;font-style:normal}
.axcient-magic-dash .amd-subhead{margin:18px 0 8px;padding:0 0 6px;border-bottom:1px solid var(--amd-border);font-size:.95em;font-weight:700;color:var(--amd-primary-dark)}
.axcient-magic-dash .amd-actions{margin:0 0 12px}
.axcient-magic-dash a.amd-button{display:inline-block;max-width:100%;padding:8px 14px;border:0;border-radius:6px;background:var(--amd-primary);color:#FFFFFF;font-weight:600;text-decoration:none;overflow-wrap:anywhere}
.axcient-magic-dash a.amd-button:hover,.axcient-magic-dash a.amd-button:focus{background:var(--amd-primary-dark);color:#FFFFFF;text-decoration:none}
.axcient-magic-dash a.amd-button:focus-visible{outline:2px solid var(--amd-primary-dark);outline-offset:2px}
.axcient-magic-dash .amd-facts{display:grid;grid-template-columns:1fr;gap:0;margin:0}
.axcient-magic-dash .basic_info__section{display:grid;grid-template-columns:minmax(110px,32%) 1fr;gap:4px 14px;align-items:baseline;margin:0;padding:8px 0;border-bottom:1px solid var(--amd-border)}
.axcient-magic-dash .basic_info__section:last-child{border-bottom:0}
.axcient-magic-dash .basic_info__section h2{margin:0;padding:0;min-width:0;max-width:100%;overflow:hidden;font-size:.9em;font-weight:600;line-height:1.45;color:var(--amd-muted);white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .basic_info__section p{margin:0;padding:0;min-width:0;max-width:100%;overflow:hidden;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-note{display:block;color:var(--amd-muted);font-size:.85em}
.axcient-magic-dash .amd-summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(100px,1fr));gap:8px;margin:0 0 12px}
.axcient-magic-dash .amd-metric{min-width:0;max-width:100%;overflow:hidden;padding:10px;border:1px solid var(--amd-border);border-radius:8px;background:var(--amd-shell);text-align:center;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-metric span{display:block;color:var(--amd-muted);font-size:.82em;font-weight:600}
.axcient-magic-dash .amd-metric strong{display:block;max-width:100%;overflow:hidden;margin-top:2px;font-size:1.25em;font-variant-numeric:tabular-nums;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-table-wrap{width:100%;max-width:100%;overflow-x:auto;overflow-y:hidden;-webkit-overflow-scrolling:touch}
.axcient-magic-dash table{width:100%;margin:0;border-collapse:collapse;table-layout:fixed;font-size:.92em;background:transparent;box-shadow:none}
.axcient-magic-dash .amd-table--appliances{min-width:460px}
.axcient-magic-dash .amd-table--counts{min-width:360px}
.axcient-magic-dash thead th{max-width:100%;overflow:hidden;padding:8px 10px;border-bottom:2px solid var(--amd-border);background:var(--amd-shell);color:var(--amd-muted);font-weight:700;text-align:left;vertical-align:bottom;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash tbody th,.axcient-magic-dash tbody td{max-width:100%;overflow:hidden;padding:8px 10px;border-bottom:1px solid var(--amd-border);text-align:left;vertical-align:top;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash tbody th{font-weight:600;color:var(--amd-ink)}
.axcient-magic-dash tbody tr:last-child th,.axcient-magic-dash tbody tr:last-child td{border-bottom:0}
.axcient-magic-dash .amd-table--counts tbody th,.axcient-magic-dash .amd-table--counts tbody td{background:#FFFFFF!important;color:#1F2430!important}
.axcient-magic-dash .amd-num{text-align:right;font-variant-numeric:tabular-nums}
.axcient-magic-dash .amd-device-scroll{width:100%;max-width:100%;max-height:520px;min-height:0;overflow:auto;overscroll-behavior:contain;scrollbar-gutter:stable;-webkit-overflow-scrolling:touch;border:1px solid var(--amd-border);border-radius:8px;background:var(--amd-surface)}
.axcient-magic-dash .amd-server-panel>.amd-device-scroll{flex:1 1 auto;min-height:140px;max-height:280px}
.axcient-magic-dash .amd-device-list{width:100%;min-width:0;max-width:100%}
.axcient-magic-dash .amd-device-grid{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1.15fr) minmax(0,.9fr) minmax(0,1fr) minmax(0,1.35fr) minmax(0,.65fr);width:100%;min-width:0;max-width:100%}
.axcient-magic-dash .amd-device-head{position:sticky;top:0;z-index:2;background:var(--amd-shell);color:var(--amd-muted);font-size:.82em;font-weight:700;text-transform:uppercase}
.axcient-magic-dash .amd-device-head>div{min-width:0;max-width:100%;overflow:hidden;padding:8px 10px;border-bottom:2px solid var(--amd-border);white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-device-row{align-items:start;border-bottom:1px solid var(--amd-border);background:var(--amd-surface)}
.axcient-magic-dash .amd-device-row:last-child{border-bottom:0}
.axcient-magic-dash .amd-device-row.amd-row--warn{background:var(--amd-warn-bg)}
.axcient-magic-dash .amd-device-cell{min-width:0;max-width:100%;overflow:hidden;padding:9px 10px;text-align:left;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-device-cell *{max-width:100%;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-device-cell--usage{text-align:right;font-variant-numeric:tabular-nums}
.axcient-magic-dash .amd-device-cell::before{display:none;margin:0 0 3px;color:var(--amd-muted);font-size:.78em;font-weight:700;line-height:1.2;text-transform:uppercase}
.axcient-magic-dash .amd-device-cell:nth-child(1)::before{content:"Device"}
.axcient-magic-dash .amd-device-cell:nth-child(2)::before{content:"System"}
.axcient-magic-dash .amd-device-cell:nth-child(3)::before{content:"Agent"}
.axcient-magic-dash .amd-device-cell:nth-child(4)::before{content:"Health"}
.axcient-magic-dash .amd-device-cell:nth-child(5)::before{content:"Recovery points"}
.axcient-magic-dash .amd-device-cell:nth-child(6)::before{content:"Vault usage"}
.axcient-magic-dash .amd-server-panel .amd-device-head{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.axcient-magic-dash .amd-server-panel .amd-device-row{grid-template-columns:repeat(2,minmax(0,1fr));margin:0;padding:4px}
.axcient-magic-dash .amd-server-panel .amd-device-cell{padding:7px 8px}
.axcient-magic-dash .amd-server-panel .amd-device-cell::before{display:block}
.axcient-magic-dash .amd-server-panel .amd-device-cell--usage{text-align:left}
.axcient-magic-dash .amd-badge{display:inline-block;max-width:100%;padding:2px 10px;border-radius:999px;font-size:.85em;font-weight:700;line-height:1.6;white-space:normal;overflow-wrap:anywhere}
.axcient-magic-dash .amd-badge--ok{background:var(--amd-ok-bg);color:var(--amd-ok-ink)}
.axcient-magic-dash .amd-badge--warn{background:var(--amd-warn-bg);color:var(--amd-warn-ink)}
.axcient-magic-dash .amd-reason{display:block;margin-top:3px;color:var(--amd-muted);font-size:.9em;overflow-wrap:anywhere}
.axcient-magic-dash .amd-rp{display:block;margin:0 0 4px}
.axcient-magic-dash .amd-links{display:flex;flex-wrap:wrap;gap:6px}
.axcient-magic-dash a.amd-chip{display:inline-block;padding:3px 10px;border:1px solid var(--amd-primary);border-radius:999px;background:var(--amd-surface);color:var(--amd-primary-dark);font-size:.85em;font-weight:600;text-decoration:none;white-space:nowrap}
.axcient-magic-dash a.amd-chip:hover,.axcient-magic-dash a.amd-chip:focus{background:var(--amd-primary);color:#FFFFFF;text-decoration:none}
.axcient-magic-dash a.amd-chip:focus-visible{outline:2px solid var(--amd-primary-dark);outline-offset:2px}
.axcient-magic-dash .amd-table--appliances a.amd-chip{white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-chip--muted{border-color:var(--amd-border);color:var(--amd-muted);font-weight:600}
.axcient-magic-dash .amd-empty{max-width:100%;overflow:hidden;margin:0;padding:16px;border:1px dashed var(--amd-border);border-radius:8px;background:var(--amd-shell);color:var(--amd-muted);text-align:center;white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}
.axcient-magic-dash .amd-warning-summary{border-color:var(--amd-warn-ink);background:var(--amd-warn-bg);color:var(--amd-warn-ink)}
.axcient-magic-dash details.mce-accordion{margin:0 0 8px;padding:8px 10px;border:1px solid var(--amd-border);border-radius:8px;background:var(--amd-surface)}
.axcient-magic-dash details.mce-accordion>summary{cursor:pointer;font-weight:600;overflow-wrap:anywhere}
.axcient-magic-dash details.mce-accordion p{margin:6px 0 0;overflow-wrap:anywhere}
@media (max-width:900px){
.axcient-magic-dash .nasa__content{grid-template-columns:1fr}
.axcient-magic-dash .amd-server-panel>.amd-device-scroll{max-height:360px}
}
@media (max-width:1100px){
.axcient-magic-dash .amd-workstation-panel .amd-device-head,.axcient-magic-dash .amd-other-device-panel .amd-device-head{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.axcient-magic-dash .amd-workstation-panel .amd-device-row,.axcient-magic-dash .amd-other-device-panel .amd-device-row{grid-template-columns:repeat(2,minmax(0,1fr));margin:0;padding:4px}
.axcient-magic-dash .amd-workstation-panel .amd-device-cell,.axcient-magic-dash .amd-other-device-panel .amd-device-cell{padding:7px 8px}
.axcient-magic-dash .amd-workstation-panel .amd-device-cell::before,.axcient-magic-dash .amd-other-device-panel .amd-device-cell::before{display:block}
.axcient-magic-dash .amd-workstation-panel .amd-device-cell--usage,.axcient-magic-dash .amd-other-device-panel .amd-device-cell--usage{text-align:left}
}
@media (max-width:640px){
.axcient-magic-dash{font-size:13px}
.axcient-magic-dash .nasa__block{padding:12px}
.axcient-magic-dash .basic_info__section{grid-template-columns:1fr;gap:2px}
.axcient-magic-dash .amd-device-row,.axcient-magic-dash .amd-server-panel .amd-device-row,.axcient-magic-dash .amd-workstation-panel .amd-device-row,.axcient-magic-dash .amd-other-device-panel .amd-device-row{grid-template-columns:1fr}
.axcient-magic-dash a.amd-button{display:block;text-align:center}
}
@container (max-width:900px){
.axcient-magic-dash .nasa__content{grid-template-columns:1fr}
.axcient-magic-dash .amd-server-panel>.amd-device-scroll{max-height:360px}
}
@container (max-width:1100px){
.axcient-magic-dash .amd-workstation-panel .amd-device-head,.axcient-magic-dash .amd-other-device-panel .amd-device-head{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}
.axcient-magic-dash .amd-workstation-panel .amd-device-row,.axcient-magic-dash .amd-other-device-panel .amd-device-row{grid-template-columns:repeat(2,minmax(0,1fr));margin:0;padding:4px}
.axcient-magic-dash .amd-workstation-panel .amd-device-cell,.axcient-magic-dash .amd-other-device-panel .amd-device-cell{padding:7px 8px}
.axcient-magic-dash .amd-workstation-panel .amd-device-cell::before,.axcient-magic-dash .amd-other-device-panel .amd-device-cell::before{display:block}
.axcient-magic-dash .amd-workstation-panel .amd-device-cell--usage,.axcient-magic-dash .amd-other-device-panel .amd-device-cell--usage{text-align:left}
}
@container (max-width:640px){
.axcient-magic-dash{font-size:13px}
.axcient-magic-dash .nasa__block{padding:12px}
.axcient-magic-dash .basic_info__section{grid-template-columns:1fr;gap:2px}
.axcient-magic-dash .amd-device-row,.axcient-magic-dash .amd-server-panel .amd-device-row,.axcient-magic-dash .amd-workstation-panel .amd-device-row,.axcient-magic-dash .amd-other-device-panel .amd-device-row{grid-template-columns:1fr}
.axcient-magic-dash a.amd-button{display:block;text-align:center}
}
.axcient-magic-dash article.amd-device-card{margin:0;padding:14px 16px;border:1px solid var(--amd-border);border-radius:10px;background:var(--amd-surface)}
.axcient-magic-dash article.amd-device-card>header{margin:0 0 12px;padding:0 0 8px;border-bottom:2px solid var(--amd-primary)}
.axcient-magic-dash article.amd-device-card>header h1{margin:0;padding:0;font-size:1.1em;font-weight:700;color:var(--amd-ink);overflow-wrap:anywhere}
</style>
'@

$script:AmdMagicDashTemplate = '<div class="axcient-magic-dash">' + $script:AmdScopedStyle + @'
<div class="nasa__content">
  <div class="amd-dashboard-column amd-dashboard-column--primary">
    <div class="nasa__block">
      <div class="nasa__block-header"><h1><i class="fas fa-info-circle icon"></i> Basic info</h1></div>
      <div class="amd-basic-content">
        <p class="amd-actions"><a class="button amd-button" href="{{client_url}}" target="_blank" rel="noopener noreferrer">Open Axcient portal</a></p>
        <article class="amd-facts">
          <div class="basic_info__section"><h2>Client name</h2><p>{{name}}</p></div>
          <div class="basic_info__section"><h2>Health status</h2><p>{{health}}</p></div>
          <div class="basic_info__section"><h2>Hudu sync date</h2><p>{{last_update}}</p></div>
          <div class="basic_info__section"><h2>Time zone</h2><p>{{time_zone}} · <span class="amd-note">Applies to all timestamps</span></p></div>
        </article>
      </div>
    </div>
    <div class="nasa__block amd-device-panel amd-server-panel">
      <div class="nasa__block-header"><h1><i class="fa-solid fa-server"></i> Servers</h1></div>
      {{server_devices}}
    </div>
  </div>
  <div class="amd-dashboard-column amd-dashboard-column--secondary">
    <div class="nasa__block">
      <div class="nasa__block-header"><h1><i class="fas fa-server icon"></i> Protected devices</h1></div>
      <div class="amd-summary-grid">
        <div class="amd-metric"><span>Healthy</span><strong>{{fleet_healthy}}</strong></div>
        <div class="amd-metric"><span>Warning</span><strong>{{fleet_warning}}</strong></div>
        <div class="amd-metric"><span>Offline</span><strong>{{fleet_offline}}</strong></div>
        <div class="amd-metric"><span>Unknown</span><strong>{{fleet_unknown}}</strong></div>
      </div>
      <article class="amd-facts">
        <div class="basic_info__section"><h2>Total vault usage</h2><p>{{total_vault_usage}} · <span class="amd-note">Private: {{private_vault_usage}} · Axcient cloud: {{cloud_vault_usage}}</span></p></div>
        <div class="basic_info__section"><h2>Local appliance usage</h2><p>{{local_appliance_usage}}</p></div>
        <div class="basic_info__section"><h2>Stale backup threshold</h2><p>{{stale_threshold}} hour(s)</p></div>
      </article>
      <h2 class="amd-subhead">Protection methods</h2>
      <div class="amd-table-wrap">
        <table class="amd-table--counts">
          <colgroup><col style="width:44%"><col style="width:28%"><col style="width:28%"></colgroup>
          <thead><tr><th scope="col">Protection</th><th scope="col" class="amd-num">Servers</th><th scope="col" class="amd-num">Workstations</th></tr></thead>
          <tbody>
            <tr><th scope="row">Appliance-based</th><td class="amd-num">{{ab_server}}</td><td class="amd-num">{{ab_workstation}}</td></tr>
            <tr><th scope="row">D2C</th><td class="amd-num">{{d2c_server}}</td><td class="amd-num">{{d2c_workstation}}</td></tr>
            <tr><th scope="row">Cloud Archive</th><td class="amd-num">{{ar_server}}</td><td class="amd-num">{{ar_workstation}}</td></tr>
          </tbody>
        </table>
      </div>
      <h2 class="amd-subhead">Appliances</h2>
      {{appliances}}
    </div>
  </div>
</div>
{{warning_section}}
<div class="nasa__block amd-device-panel amd-workstation-panel">
  <div class="nasa__block-header"><h1><i class="fa-solid fa-desktop"></i> Workstations</h1></div>
  {{workstation_devices}}
</div>
{{other_device_section}}
</div>
'@

$script:AmdMagicDashWarningSectionTemplate = @'
<div class="nasa__block">
  <div class="nasa__block-header"><h1><i class="fa-solid fa-triangle-exclamation"></i> Warnings ({{warning_count}})</h1></div>
  <p class="amd-empty amd-warning-summary">{{warning_summary}}</p>
</div>
'@

$script:AmdMagicDashOtherDeviceSectionTemplate = @'
<div class="nasa__block amd-device-panel amd-other-device-panel">
  <div class="nasa__block-header"><h1><i class="fa-solid fa-circle-question"></i> Other devices</h1></div>
  {{other_devices}}
</div>
'@

$script:AmdDeviceCardOwnershipMarkerPrefix = '<!-- AXCIENT-MAGIC-DASH:device:v1:'

$script:AmdDeviceCardTemplate = '<div class="axcient-magic-dash">' + $script:AmdScopedStyle + @'
{{ownership_marker}}
<article class="amd-device-card">
  <header>
    <h1>{{name}}</h1>
    <p class="amd-note">{{type}} · {{protection_method}}</p>
  </header>
  <dl class="amd-facts">
    <div class="basic_info__section"><h2>Axcient device ID</h2><p>{{device_id}}</p></div>
    <div class="basic_info__section"><h2>Operating system</h2><p>{{operating_system}}</p></div>
    <div class="basic_info__section"><h2>IP address</h2><p>{{ip_address}}</p></div>
    <div class="basic_info__section"><h2>Agent</h2><p>{{agent_status}} · <span class="amd-note">Version: {{agent_version}}</span></p></div>
    <div class="basic_info__section"><h2>Health</h2><p>{{health}}</p></div>
    <div class="basic_info__section"><h2>Local recovery</h2><p>{{local_recovery}}</p></div>
    <div class="basic_info__section"><h2>Cloud recovery</h2><p>{{cloud_recovery}}</p></div>
    <div class="basic_info__section"><h2>Vault usage</h2><p>{{vault_usage}}</p></div>
  </dl>
  <p class="amd-actions"><a class="amd-button" href="{{details_url}}" target="_blank" rel="noopener noreferrer">Open in Axcient</a></p>
</article>
</div>
'@

function New-AmdDeviceCardHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$DeviceState,
        [Parameter(Mandatory)][int64]$AxcientDeviceId
    )

    $health = New-AmdStatusBadge -Status $DeviceState.HealthStatus -Reason $DeviceState.HealthReason
    $stale = if ($DeviceState.IsStale) { ' <span class="amd-badge amd-badge--warn">Stale backup</span>' } else { '' }
    Merge-AmdTemplate -Template $script:AmdDeviceCardTemplate -Values @{
        ownership_marker   = "$($script:AmdDeviceCardOwnershipMarkerPrefix)$AxcientDeviceId -->"
        name               = ConvertTo-AmdHtml $DeviceState.Name
        device_id          = ConvertTo-AmdHtml ([string]$AxcientDeviceId)
        type               = ConvertTo-AmdHtml $DeviceState.Type
        protection_method  = ConvertTo-AmdHtml $DeviceState.ProtectionMethod
        operating_system   = ConvertTo-AmdHtml $DeviceState.OperatingSystem
        ip_address         = ConvertTo-AmdHtml $DeviceState.IpAddress
        agent_status       = ConvertTo-AmdHtml $DeviceState.AgentStatus
        agent_version      = ConvertTo-AmdHtml $DeviceState.AgentVersion
        health             = $health
        local_recovery     = (ConvertTo-AmdHtml $DeviceState.LocalRecoveryPoint.Display) + $stale
        cloud_recovery     = ConvertTo-AmdHtml $DeviceState.CloudRecoveryPoint.Display
        vault_usage        = ConvertTo-AmdHtml $DeviceState.VaultUsage
        details_url        = ConvertTo-AmdSafeHref $DeviceState.DetailsUrl
    }
}
