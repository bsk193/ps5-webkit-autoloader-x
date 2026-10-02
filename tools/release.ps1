<#
.SYNOPSIS
    Creates and pushes a WebKit Autoloader X release tag (wkx-v<version>), which starts
    the GitHub "Release" workflow.

.DESCRIPTION
    Release      wkx-v1.2.3          -> GitHub release, marked Latest
    Pre-release  wkx-v1.2.3-beta.1   -> GitHub pre-release (alpha / beta / rc)

    Checks before tagging: working tree clean, on main, main up to date with
    the fork remote, tag not taken. Versions are computed from the existing wkx-v* tags.

.EXAMPLE
    .\tools\release.ps1 -Bump patch                 # 1.0.0 -> wkx-v1.0.1
.EXAMPLE
    .\tools\release.ps1 -Bump minor -Pre beta       # 1.0.1 -> wkx-v1.1.0-beta.1
.EXAMPLE
    .\tools\release.ps1 -Pre beta                   # next beta of the pending pre-release: wkx-v1.1.0-beta.2
.EXAMPLE
    .\tools\release.ps1 -Pre rc                     # switch to release candidate: wkx-v1.1.0-rc.1
.EXAMPLE
    .\tools\release.ps1 -Promote                    # wkx-v1.1.0-rc.1 -> stable wkx-v1.1.0
.EXAMPLE
    .\tools\release.ps1 -Version 2.0.0-rc.1 -DryRun # explicit version, show what would happen
#>
[CmdletBinding(DefaultParameterSetName = 'Bump')]
param(
    # Next stable version relative to the latest stable release.
    [Parameter(ParameterSetName = 'Bump')]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump,

    # Make it a pre-release of this kind. Without -Bump, continues the pending pre-release.
    [Parameter(ParameterSetName = 'Bump')]
    [ValidateSet('alpha', 'beta', 'rc')]
    [string]$Pre,

    # Release the latest pre-release's version as stable (1.1.0-rc.2 -> 1.1.0).
    [Parameter(ParameterSetName = 'Promote', Mandatory = $true)]
    [switch]$Promote,

    # Exact version, e.g. 1.2.3 or 1.2.3-beta.1 (without the wkx-v prefix).
    [Parameter(ParameterSetName = 'Explicit', Mandatory = $true)]
    [string]$Version,

    # Tag message (defaults to "WebKit Autoloader X <version>").
    [string]$Message,

    # Show what would be tagged without creating or pushing anything.
    [switch]$DryRun,

    # Skip the confirmation prompt.
    [switch]$Yes,

    # Allow releasing from a branch other than main (the workflow still refuses
    # commits that are not on main).
    [switch]$AllowNonMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Repo = 'bsk193/ps5-webkit-autoloader-x'
$VersionRe = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(alpha|beta|rc)\.(0|[1-9]\d*))?$'
$PreOrder = @{ 'alpha' = 0; 'beta' = 1; 'rc' = 2 }

function Fail([string]$msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

# ── git ─────────────────────────────────────────────────────────────────
$Git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $Git) {
    foreach ($p in 'C:\Program Files\Git\cmd\git.exe', 'C:\Program Files (x86)\Git\cmd\git.exe') {
        if (Test-Path $p) { $Git = $p; break }
    }
}
if (-not $Git) { Fail 'git not found. Install Git for Windows.' }

function Invoke-Git {
    $out = & $Git @args 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "git $($args -join ' ') failed:`n$out" }
    return $out
}

$root = (Invoke-Git rev-parse --show-toplevel | Select-Object -First 1).Trim()
Set-Location $root

# The remote that points at this fork: "fork" in the maintainer's clone (where
# "upstream" is itsPLK), "origin" in a plain clone.
$Remote = $null
foreach ($r in (Invoke-Git remote)) {
    $url = (& $Git remote get-url $r.Trim() 2>$null | Select-Object -First 1)
    if ($url -match 'bsk193/ps5-webkit-autoloader-x(\.git)?/?$') { $Remote = $r.Trim(); break }
}
if (-not $Remote) { Fail "No git remote points at github.com/$Repo." }

# ── versions ───────────────────────────────────────────────────────────
function ConvertTo-Ver([string]$s) {
    $m = [regex]::Match($s, $VersionRe)
    if (-not $m.Success) { return $null }
    [pscustomobject]@{
        Text    = $s
        Major   = [int]$m.Groups[1].Value
        Minor   = [int]$m.Groups[2].Value
        Patch   = [int]$m.Groups[3].Value
        PreKind = $m.Groups[4].Value
        PreNum  = if ($m.Groups[5].Success) { [int]$m.Groups[5].Value } else { 0 }
    }
}

# Semver-style sort key: pre-releases sort before their stable version.
function Get-SortKey($v) {
    $pre = if ($v.PreKind) { '{0}{1:D6}' -f $PreOrder[$v.PreKind], $v.PreNum } else { '9999999' }
    '{0:D6}.{1:D6}.{2:D6}.{3}' -f $v.Major, $v.Minor, $v.Patch, $pre
}

function Format-Ver([int]$maj, [int]$min, [int]$pat, [string]$kind, [int]$num) {
    $s = "$maj.$min.$pat"
    if ($kind) { $s += "-$kind.$num" }
    $s
}

Write-Host "Fetching $Remote (branches and tags)..." -ForegroundColor DarkGray
# No --prune: with --tags it would delete the upstream v* tags fetched from itsPLK.
Invoke-Git fetch --quiet --tags $Remote | Out-Null

$all = @(Invoke-Git tag -l 'wkx-v*' | ForEach-Object { ConvertTo-Ver ($_.Trim() -replace '^wkx-v', '') } | Where-Object { $_ })
$all = @($all | Sort-Object { Get-SortKey $_ })
$latest = if ($all.Count) { $all[-1] } else { $null }
$stable = @($all | Where-Object { -not $_.PreKind })
$latestStable = if ($stable.Count) { $stable[-1] } else { $null }
$pending = if ($latest -and $latest.PreKind) { $latest } else { $null }  # pre-release newer than any stable

function Get-NextPreNum([int]$maj, [int]$min, [int]$pat, [string]$kind) {
    $same = @($all | Where-Object { $_.Major -eq $maj -and $_.Minor -eq $min -and $_.Patch -eq $pat -and $_.PreKind -eq $kind })
    if ($same.Count) { ($same | Measure-Object -Property PreNum -Maximum).Maximum + 1 } else { 1 }
}

switch ($PSCmdlet.ParameterSetName) {
    'Explicit' {
        $new = $Version.Trim() -replace '^wkx-v', '' -replace '^v', ''
        if (-not (ConvertTo-Ver $new)) {
            Fail "Invalid version '$new'. Use 1.2.3 or 1.2.3-beta.1 (alpha/beta/rc)."
        }
    }
    'Promote' {
        if (-not $pending) {
            if ($latest) { Fail "No pending pre-release to promote (the latest tag wkx-v$($latest.Text) is already stable)." }
            Fail 'No releases yet, nothing to promote. Start with e.g. -Bump major -Pre beta'
        }
        $new = Format-Ver $pending.Major $pending.Minor $pending.Patch '' 0
    }
    'Bump' {
        if ($Bump) {
            $b = if ($latestStable) { $latestStable } else { $null }
            if (-not $b) {
                $maj, $min, $pat = 1, 0, 0            # first release ever
            } else {
                switch ($Bump) {
                    'major' { $maj, $min, $pat = ($b.Major + 1), 0, 0 }
                    'minor' { $maj, $min, $pat = $b.Major, ($b.Minor + 1), 0 }
                    'patch' { $maj, $min, $pat = $b.Major, $b.Minor, ($b.Patch + 1) }
                }
            }
            if ($Pre) {
                $new = Format-Ver $maj $min $pat $Pre (Get-NextPreNum $maj $min $pat $Pre)
            } else {
                $new = Format-Ver $maj $min $pat '' 0
            }
        } elseif ($Pre) {
            if (-not $pending) {
                Fail "No pending pre-release to continue. Start one with e.g. -Bump minor -Pre $Pre"
            }
            if ($PreOrder[$Pre] -lt $PreOrder[$pending.PreKind]) {
                Fail "Pending pre-release is $($pending.Text); going back to '$Pre' is not allowed."
            }
            $new = Format-Ver $pending.Major $pending.Minor $pending.Patch $Pre (Get-NextPreNum $pending.Major $pending.Minor $pending.Patch $Pre)
        } else {
            Write-Host 'Choose what to release, e.g.:' -ForegroundColor Yellow
            Write-Host '  .\tools\release.ps1 -Bump patch            stable x.y.Z'
            Write-Host '  .\tools\release.ps1 -Bump minor -Pre beta  pre-release x.Y.0-beta.1'
            Write-Host '  .\tools\release.ps1 -Pre beta              next beta of the pending pre-release'
            Write-Host '  .\tools\release.ps1 -Promote               pending pre-release -> stable'
            Write-Host '  .\tools\release.ps1 -Version 1.2.3         explicit'
            Write-Host ''
            Write-Host ("Latest stable: {0}   Latest tag: {1}" -f `
                    ($(if ($latestStable) { $latestStable.Text } else { '(none)' })), `
                    ($(if ($latest) { $latest.Text } else { '(none)' })))
            exit 1
        }
    }
}

$newVer = ConvertTo-Ver $new
$tag = "wkx-v$new"
$isPre = [bool]$newVer.PreKind

if ($latest -and (Get-SortKey $newVer) -le (Get-SortKey $latest) -and $PSCmdlet.ParameterSetName -eq 'Explicit') {
    Write-Host "WARNING: $new is not newer than the latest tag $($latest.Text)." -ForegroundColor Yellow
}

# ── pre-flight checks (all collected; a dry run shows them as warnings) ──
$problems = New-Object System.Collections.Generic.List[string]

if ((Invoke-Git tag -l $tag)) { $problems.Add("Tag $tag already exists.") }
$remoteTag = & $Git ls-remote --tags $Remote "refs/tags/$tag" 2>$null
if ($remoteTag) { $problems.Add("Tag $tag already exists on $Remote.") }

$dirty = Invoke-Git status --porcelain
if ($dirty) { $problems.Add("Working tree has uncommitted changes. Commit or stash them first.") }

$branch = (Invoke-Git rev-parse --abbrev-ref HEAD | Select-Object -First 1).Trim()
if ($branch -ne 'main' -and -not $AllowNonMain) {
    $problems.Add("You are on '$branch'. Releases are made from main: git checkout main; git pull")
}

$head = (Invoke-Git rev-parse HEAD | Select-Object -First 1).Trim()
& $Git merge-base --is-ancestor $head "$Remote/main" 2>$null
if ($LASTEXITCODE -ne 0) {
    $problems.Add("HEAD ($($head.Substring(0,7))) is not on $Remote/main. Merge/push to main first (the Release workflow refuses it otherwise).")
}
if ($branch -eq 'main') {
    $behind = (Invoke-Git rev-list --count "HEAD..$Remote/main" | Select-Object -First 1).Trim()
    if ([int]$behind -gt 0) { $problems.Add("Local main is $behind commit(s) behind $Remote/main. Run: git pull $Remote main") }
}

$upstream = ''
$vh = Get-Content (Join-Path $root 'include/wkali.h') -Raw
$mUp = [regex]::Match($vh, '#define\s+WKAL_VERSION\s+"([^"]+)"')
if ($mUp.Success) { $upstream = $mUp.Groups[1].Value }

if (-not $Message) { $Message = "WebKit Autoloader X $new" }
$subject = (Invoke-Git log -1 --format=%s | Select-Object -First 1)

# ── summary + confirm ────────────────────────────────────────────────────
Write-Host ''
Write-Host '  WebKit Autoloader X release' -ForegroundColor Cyan
Write-Host ("  Tag         : {0}" -f $tag)
Write-Host ("  Type        : {0}" -f $(if ($isPre) { "PRE-RELEASE ($($newVer.PreKind)), not marked Latest" } else { 'RELEASE, marked Latest' }))
Write-Host ("  Based on    : WebKit Autoloader v{0}" -f $upstream)
Write-Host ("  Commit      : {0} {1}" -f $head.Substring(0, 7), $subject)
Write-Host ("  Previous    : {0}" -f $(if ($latest) { "wkx-v$($latest.Text)" } else { '(first release)' }))
Write-Host ''

if ($problems.Count) {
    foreach ($p in $problems) { Write-Host "  ! $p" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Red' }) }
    Write-Host ''
}

if ($DryRun) {
    Write-Host 'Dry run: nothing was tagged or pushed.' -ForegroundColor Yellow
    exit 0
}
if ($problems.Count) { Fail 'Fix the problems above, then run the script again.' }

if (-not $Yes) {
    $answer = Read-Host "Create and push $tag? [y/N]"
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Aborted.'; exit 1 }
}

Invoke-Git tag -a $tag -m $Message | Out-Null
$push = & $Git push $Remote "refs/tags/$tag" 2>&1
if ($LASTEXITCODE -ne 0) {
    & $Git tag -d $tag 2>&1 | Out-Null
    Fail "Push failed (local tag removed):`n$push"
}

Write-Host ''
Write-Host "Pushed $tag. The Release workflow is building it now:" -ForegroundColor Green
Write-Host "  https://github.com/$Repo/actions/workflows/release.yml"
Write-Host "  Release page (when done): https://github.com/$Repo/releases/tag/$tag"
