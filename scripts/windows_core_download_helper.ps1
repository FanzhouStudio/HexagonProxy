param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [int]$ProxyPort = 0,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$response = $null
$inputStream = $null
$outputStream = $null
$result = @{ ok = $false; status = 0; message = '' }
try {
    if (-not $Url.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Only HTTPS downloads are supported.'
    }
    # Use Windows TLS and its trusted certificate store. Never bypass validation.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.UserAgent = 'HexagonProxy'
    $request.Accept = 'application/vnd.github+json'
    $request.AllowAutoRedirect = $true
    $request.MaximumAutomaticRedirections = 8
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = $TimeoutSeconds * 1000
    $request.AutomaticDecompression = [Net.DecompressionMethods]::None
    if ($ProxyPort -gt 0) {
        $request.Proxy = New-Object Net.WebProxy("http://127.0.0.1:$ProxyPort")
    }
    # Otherwise retain the Windows system proxy, including another client's proxy.
    $response = $request.GetResponse()
    $result.status = [int]$response.StatusCode
    if ($response.ResponseUri.Scheme -ne 'https') { throw 'Insecure redirect rejected.' }
    $inputStream = $response.GetResponseStream()
    $outputStream = [IO.File]::Create($OutputPath)
    $inputStream.CopyTo($outputStream)
    $result.ok = $result.status -eq 200
} catch {
    $result.message = $_.Exception.Message
    if ($_.Exception.Response) { $result.status = [int]$_.Exception.Response.StatusCode }
} finally {
    if ($outputStream) { $outputStream.Dispose() }
    if ($inputStream) { $inputStream.Dispose() }
    if ($response) { $response.Dispose() }
}
# Publish only after the output has closed, so the caller never sees partial success.
[IO.File]::WriteAllText($ResultPath + '.tmp', ($result | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath ($ResultPath + '.tmp') -Destination $ResultPath -Force
