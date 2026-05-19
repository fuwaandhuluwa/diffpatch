# Compare two directories file-by-file using SHA256
# Usage: _compare_dirs.ps1 <dir_a> <dir_b>
# Exit 0 = match, 1 = differences, 2 = identical (both empty or same set)
param(
    [Parameter(Mandatory)][string]$DirA,
    [Parameter(Mandatory)][string]$DirB
)

$srcPath = (Resolve-Path $DirA).Path
$dstPath = (Resolve-Path $DirB).Path

$a = Get-ChildItem $srcPath -Recurse -File | ForEach-Object {
    [PSCustomObject]@{
        Rel  = $_.FullName.Substring($srcPath.Length).TrimStart('\')
        Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
} | Sort-Object Rel

$b = Get-ChildItem $dstPath -Recurse -File | ForEach-Object {
    [PSCustomObject]@{
        Rel  = $_.FullName.Substring($dstPath.Length).TrimStart('\')
        Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
} | Sort-Object Rel

$diff = Compare-Object $a $b -Property Rel, Hash

if (-not $diff) {
    Write-Host '  [PASS] All files match.' -ForegroundColor Green
    Write-Host "  Total files checked: $($a.Count)"
    exit 0
}

# Build hash tables for detailed report
$ah = @{}; foreach ($x in $a) { $ah[$x.Rel] = $x.Hash }
$bh = @{}; foreach ($x in $b) { $bh[$x.Rel] = $x.Hash }
$rels = ($ah.Keys + $bh.Keys) | Sort-Object -Unique

Write-Host '  [FAIL] Differences detected:' -ForegroundColor Red
foreach ($r in $rels) {
    if (-not $ah.ContainsKey($r))     { Write-Host "    [MISSING] $r" -ForegroundColor Yellow }
    elseif (-not $bh.ContainsKey($r)) { Write-Host "    [EXTRA]   $r" -ForegroundColor Yellow }
    elseif ($ah[$r] -ne $bh[$r])      { Write-Host "    [MISMATCH] $r" -ForegroundColor Red }
}
exit 1
