param(
    [string]$Version = '0.1.0'
)

$ErrorActionPreference = 'Stop'
$repo = 'nyoungk-design/racodock-site'
$tag = "doong2dock-android-v$Version"
$name = "Doong2Dock-Android-v$Version-TEST.apk"
$apkPath = Join-Path $PSScriptRoot "..\..\doong2dockapp\release\v$Version\$name"
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "APK not found: $apkPath"
}
$apkFile = Get-Item -LiteralPath $apkPath
$sha = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()

# Request the existing Git Credential Manager secret only at execution time.
# The token must never be saved in a repository, script, terminal log or release notes.
$env:GCM_INTERACTIVE = 'never'
$env:GIT_TERMINAL_PROMPT = '0'
$credLines = @( "protocol=https`nhost=github.com`n`n" | git -c credential.interactive=never credential fill )
$tokenLine = $credLines | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
if (-not $tokenLine) { throw 'Existing GitHub credential not available.' }
$token = $tokenLine.Substring(9)
$credLines = $null
$tokenLine = $null

$headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'Doong2Dock-Release-Publisher'
}
$root = "https://api.github.com/repos/$repo"
try {
    try {
        $release = Invoke-RestMethod -Uri "$root/releases/tags/$tag" -Headers $headers -TimeoutSec 30
    } catch {
        if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404) { throw }
        $body = @{
            tag_name = $tag
            target_commitish = 'main'
            name = "Doong2Dock Android Viewer v$Version (test build)"
            draft = $false
            prerelease = $true
            body = @"
### Android-only local document viewer (test build)

- No user account, Microsoft / Hancom login, cloud upload, or editing.
- Local document viewing for HWP/HWPX, DOCX, XLSX, PPTX, PDF, images, TXT and other formats.
- Built with the existing Doong2Dock mascot. Android APK, v$Version.
- This is a preview: HWP/HWPX and other formats are not yet verified across real devices. Layout may differ from original documents.
- APK was built with development signing credentials. It is not a Google Play-signed production release.

SHA-256 ($name): $sha
Size: $($apkFile.Length) bytes
"@
        } | ConvertTo-Json -Depth 5
        $release = Invoke-RestMethod -Method Post -Uri "$root/releases" -Headers $headers -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 45
    }

    if ($release.draft) { throw 'Release is still draft; cannot publish a link.' }
    $asset = @($release.assets) | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($asset) {
        if ([int64]$asset.size -ne [int64]$apkFile.Length) {
            throw "Existing release asset size mismatch. Refusing to overwrite $name"
        }
        Write-Output "Release asset already exists: $($asset.browser_download_url)"
    } else {
        $uploadBase = ($release.upload_url -replace '\{.*$','')
        $uploadUri = "$uploadBase`?name=$([uri]::EscapeDataString($name))"
        # Stream the binary directly to the releases asset endpoint.
        $asset = Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers -InFile $apkFile.FullName -ContentType 'application/vnd.android.package-archive' -TimeoutSec 300
        if ($asset.state -ne 'uploaded' -or [int64]$asset.size -ne [int64]$apkFile.Length) {
            throw 'Release upload returned unexpected asset state or size.'
        }
        Write-Output "Uploaded release asset: $($asset.browser_download_url)"
    }
    Write-Output "TAG=$tag"
    Write-Output "APK_BYTES=$($apkFile.Length)"
    Write-Output "APK_SHA256=$sha"
} finally {
    $token = $null
    $headers = $null
}
