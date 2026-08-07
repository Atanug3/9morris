$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repositoryRoot

node .\tests\browser-authoritative.test.js
if ($LASTEXITCODE -ne 0) {
  throw 'Browser authoritative tests failed.'
}

$supabase = Get-Command supabase -ErrorAction SilentlyContinue
if (-not $supabase) {
  $scoopShim = Join-Path $HOME 'scoop\shims\supabase.exe'
  if (-not (Test-Path $scoopShim)) {
    throw 'Supabase CLI was not found.'
  }
  $supabase = $scoopShim
}

& $supabase test db --local .\supabase\tests
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase database tests failed.'
}

Write-Output 'All local authoritative tests passed.'
