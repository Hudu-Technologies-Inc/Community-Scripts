$huduExceptionType = 'Amd.HuduApiException' -as [type]
if ($null -eq $huduExceptionType) {
    Add-Type -TypeDefinition @'
namespace Amd
{
    public sealed class HuduApiException : System.Exception
    {
        public int? StatusCode { get; private set; }
        public string Kind { get; private set; }

        public HuduApiException(string message, string kind, int statusCode)
            : base(message)
        {
            Kind = kind;
            StatusCode = statusCode >= 0 ? statusCode : (int?)null;
        }
    }
}
'@ -ErrorAction Stop
}

$boundedReaderType = 'Amd.BoundedTextReader' -as [type]
if ($null -eq $boundedReaderType) {
    Add-Type -TypeDefinition @'
namespace Amd
{
    public static class BoundedTextReader
    {
        public static async System.Threading.Tasks.Task<string> ReadToEndAsync(
            System.IO.TextReader reader,
            int maximumCharacters)
        {
            var result = new System.Text.StringBuilder(maximumCharacters);
            var buffer = new char[1024];
            int read;
            while ((read = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) > 0)
            {
                int remaining = maximumCharacters - result.Length;
                if (remaining > 0)
                {
                    result.Append(buffer, 0, System.Math.Min(read, remaining));
                }
            }
            return result.ToString();
        }
    }
}
'@ -ErrorAction Stop
}

$script:AmdHuduBridgeState = $null
$script:AmdHuduBridgeMaxFrameBytes = 16MB
$script:AmdHuduBridgeDefaultTimeoutSec = 420

function Resolve-AmdHuduBridgePaths {
    [CmdletBinding()]
    param()

    $moduleRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $moduleRoot))
    $runtimeRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'Runtime'))

    if ($env:AMD_VERIFIED_ELEVATION -eq '1') {
        if ([string]::IsNullOrWhiteSpace($env:AMD_VERIFIED_RUNTIME_ROOT)) {
            throw 'The verified Python runtime root was not provided to the elevated process.'
        }
        $verifiedRuntimeRoot = [IO.Path]::GetFullPath($env:AMD_VERIFIED_RUNTIME_ROOT)
        if (-not [string]::Equals($verifiedRuntimeRoot.TrimEnd('\'), $runtimeRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The bundled Python runtime is not inside the verified elevation snapshot.'
        }
        $runtimeRoot = $verifiedRuntimeRoot
    }

    $pythonPath = [IO.Path]::GetFullPath((Join-Path $runtimeRoot 'python-3.12.10-embed-amd64\python.exe'))
    $bridgePath = [IO.Path]::GetFullPath((Join-Path $moduleRoot 'Bridge\hudu_bridge.py'))
    foreach ($requiredPath in $pythonPath, $bridgePath) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required Hudu bridge file is missing: $requiredPath"
        }
        $item = Get-Item -LiteralPath $requiredPath -Force -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType) -or $null -ne $item.Target) {
            throw "The Hudu bridge cannot execute a symbolic link or junction: $requiredPath"
        }
    }

    return [pscustomobject]@{
        Python = $pythonPath
        Bridge = $bridgePath
    }
}

function Get-AmdHuduBridgeStderr {
    [CmdletBinding()]
    param([AllowNull()]$State)

    if ($null -eq $State -or $null -eq $State.StderrTask -or -not $State.StderrTask.IsCompleted) {
        return ''
    }
    try {
        $text = [string]$State.StderrTask.GetAwaiter().GetResult()
        return ConvertTo-AmdRedactedText $text
    }
    catch {
        return ''
    }
}

function Stop-AmdHuduBridgeProcess {
    [CmdletBinding()]
    param([AllowNull()]$State)

    if ($null -eq $State) { return }
    try { $State.Process.StandardInput.Close() }
    catch { Write-Verbose 'The Hudu bridge input stream was already closed.' }
    try {
        if (-not $State.Process.HasExited -and -not $State.Process.WaitForExit(2000)) {
            $State.Process.Kill($true)
            $null = $State.Process.WaitForExit(5000)
        }
    }
    catch {
        Write-Verbose "The Hudu bridge process could not be stopped cleanly: $(ConvertTo-AmdRedactedText $_.Exception.Message)"
    }
    try { $State.Process.Dispose() }
    catch { Write-Verbose 'The Hudu bridge process was already disposed.' }
    try { $State.Gate.Dispose() }
    catch { Write-Verbose 'The Hudu bridge request gate was already disposed.' }
}

function New-AmdHuduBridgeException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()]$StatusCode
    )

    $status = -1
    if ($null -ne $StatusCode) {
        try { $status = [int]$StatusCode }
        catch { $status = -1 }
    }
    $type = 'Amd.HuduApiException' -as [type]
    return [Activator]::CreateInstance($type, @(
        [string](ConvertTo-AmdRedactedText $Message),
        [string]$Kind,
        [int]$status
    ))
}

function Invoke-AmdHuduOp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Operation,
        [AllowNull()][hashtable]$Arguments = @{},
        [ValidateRange(1, 1800)][int]$TimeoutSec = $script:AmdHuduBridgeDefaultTimeoutSec
    )

    $state = $script:AmdHuduBridgeState
    if ($null -eq $state -or $null -eq $state.Process) {
        throw [InvalidOperationException]::new('The Hudu bridge is not connected.')
    }

    $deadline = [Diagnostics.Stopwatch]::StartNew()
    $gateAcquired = $false
    $requestWasSent = $false
    $responseWasValidated = $false
    try {
        if (-not $state.Gate.Wait([TimeSpan]::FromSeconds($TimeoutSec))) {
            throw [TimeoutException]::new("The Hudu operation '$Operation' timed out while waiting for another request to finish.")
        }
        $gateAcquired = $true
        if ($state.Process.HasExited) {
            $stderr = Get-AmdHuduBridgeStderr -State $state
            $detail = if ([string]::IsNullOrWhiteSpace($stderr)) { '' } else { " $stderr" }
            throw [InvalidOperationException]::new("The Hudu bridge stopped before the request could be sent.$detail")
        }

        $state.NextId++
        $requestId = [int64]$state.NextId
        $frame = @{
            id   = $requestId
            op   = $Operation
            args = if ($null -eq $Arguments) { @{} } else { $Arguments }
        } | ConvertTo-Json -Compress -Depth 100
        # Python's frame limit includes the newline delimiter. Standardize on a
        # one-byte LF below and reserve it here so an exact-boundary frame cannot
        # pass PowerShell validation only to be rejected by the bridge.
        if ([Text.Encoding]::UTF8.GetByteCount($frame) + 1 -gt $script:AmdHuduBridgeMaxFrameBytes) {
            throw [ArgumentException]::new('The Hudu bridge request exceeds the maximum frame size.')
        }

        $state.Process.StandardInput.WriteLine($frame)
        $state.Process.StandardInput.Flush()
        $requestWasSent = $true
        $readTask = $state.Process.StandardOutput.ReadLineAsync()
        $remaining = [TimeSpan]::FromSeconds($TimeoutSec) - $deadline.Elapsed
        if ($remaining -le [TimeSpan]::Zero -or -not $readTask.Wait($remaining)) {
            $script:AmdHuduBridgeState = $null
            Stop-AmdHuduBridgeProcess -State $state
            throw [TimeoutException]::new("The Hudu operation '$Operation' exceeded its $TimeoutSec-second timeout. The bridge was stopped safely.")
        }
        $line = $readTask.GetAwaiter().GetResult()
        if ($null -eq $line) {
            $stderr = Get-AmdHuduBridgeStderr -State $state
            $detail = if ([string]::IsNullOrWhiteSpace($stderr)) { '' } else { " $stderr" }
            throw [InvalidOperationException]::new("The Hudu bridge stopped during '$Operation'.$detail")
        }
        # ReadLineAsync strips the LF delimiter that Python counted before
        # writing, so reserve that byte here to keep both frame limits identical.
        if ([Text.Encoding]::UTF8.GetByteCount($line) + 1 -gt $script:AmdHuduBridgeMaxFrameBytes) {
            throw [IO.InvalidDataException]::new('The Hudu bridge response exceeds the maximum frame size.')
        }
        try { $response = $line | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
        catch {
            throw [IO.InvalidDataException]::new('The Hudu bridge wrote invalid protocol data to stdout.')
        }
        if ($null -eq $response -or [int64]$response.id -ne $requestId -or $response.ok -isnot [bool]) {
            throw [IO.InvalidDataException]::new('The Hudu bridge response did not match the pending request.')
        }
        if (-not $response.ok) {
            $errorInfo = $response.error
            if ($null -eq $errorInfo) {
                throw [IO.InvalidDataException]::new('The Hudu bridge returned an invalid error response.')
            }
            $bridgeException = New-AmdHuduBridgeException -Message ([string]$errorInfo.message) -Kind ([string]$errorInfo.kind) -StatusCode $errorInfo.status
            $responseWasValidated = $true
            throw $bridgeException
        }
        $responseWasValidated = $true
        return $response.data
    }
    catch {
        $transportFailed =
            $_.Exception -is [IO.IOException] -or
            $_.Exception -is [IO.InvalidDataException] -or
            $_.Exception -is [ObjectDisposedException] -or
            ($requestWasSent -and -not $responseWasValidated)
        if (-not $transportFailed) {
            try { $transportFailed = $state.Process.HasExited }
            catch { $transportFailed = $true }
        }
        if ($transportFailed) {
            $script:AmdHuduBridgeState = $null
            Stop-AmdHuduBridgeProcess -State $state
        }
        throw
    }
    finally {
        if ($gateAcquired -and $null -ne $state.Gate) {
            try { $state.Gate.Release() | Out-Null }
            catch { Write-Verbose 'The Hudu bridge request gate was already disposed.' }
        }
    }
}

function Start-AmdHuduBridge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InstanceUrl,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ApiKey
    )

    Set-AmdSensitiveValues -Values @($ApiKey) -Add
    Stop-AmdHuduBridge
    $paths = Resolve-AmdHuduBridgePaths
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $paths.Python
    foreach ($argument in '-I', '-S', '-E', '-B', $paths.Bridge) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.WorkingDirectory = Split-Path -Parent $paths.Python
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $null = $startInfo.Environment.Remove('PYTHONHOME')
    $null = $startInfo.Environment.Remove('PYTHONPATH')

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $state = $null
    try {
        if (-not $process.Start()) {
            throw [InvalidOperationException]::new('The bundled Python process did not start.')
        }
        $process.StandardInput.NewLine = "`n"
        $state = [pscustomobject]@{
            Process    = $process
            StderrTask = [Amd.BoundedTextReader]::ReadToEndAsync($process.StandardError, 4096)
            Gate       = [Threading.SemaphoreSlim]::new(1, 1)
            NextId     = [int64]0
        }
        $script:AmdHuduBridgeState = $state
        $null = Invoke-AmdHuduOp -Operation init -Arguments @{
            api_key     = $ApiKey
            instance_url = $InstanceUrl
        } -TimeoutSec 60
        $heartbeat = Invoke-AmdHuduOp -Operation heartbeat -TimeoutSec 15
        if ($null -eq $heartbeat -or -not $heartbeat.ready) {
            throw [InvalidOperationException]::new('The Hudu bridge did not become ready.')
        }
    }
    catch {
        $script:AmdHuduBridgeState = $null
        if ($null -ne $state) { Stop-AmdHuduBridgeProcess -State $state }
        else {
            try { if (-not $process.HasExited) { $process.Kill($true) } }
            catch { Write-Verbose 'The partially started Hudu bridge had already stopped.' }
            $process.Dispose()
        }
        throw
    }
}

function Stop-AmdHuduBridge {
    [CmdletBinding()]
    param()

    $state = $script:AmdHuduBridgeState
    if ($null -eq $state) { return }
    try { $null = Invoke-AmdHuduOp -Operation shutdown -TimeoutSec 2 }
    catch { Write-Verbose "The Hudu bridge did not acknowledge shutdown: $(ConvertTo-AmdRedactedText $_.Exception.Message)" }
    finally {
        $script:AmdHuduBridgeState = $null
        Stop-AmdHuduBridgeProcess -State $state
    }
}
