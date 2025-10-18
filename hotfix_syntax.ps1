# hotfix_syntax.ps1
param(
  [string]$RepoDir = "C:\fortune_ai_server_pro_lunar",
  [string]$CommitMsg = "hotfix: remove corrupted elif line (encoding issue) and enforce UTF-8"
)

Set-Location $RepoDir

$main = Join-Path $RepoDir "main.py"
if (-not (Test-Path $main)) {
  Write-Error "main.py not found at $main"
  exit 1
}

# 1) 파일을 통째로 읽고, 깨진 elif 라인을 안전하게 무력화
$content = Get-Content $main -Raw

# - 'elif L.startswith(...) :' 형태로 시작하는 라인 중 괄호가 깨진/비정상 문자열을 전부 False 처리
# - 너무 공격적이지 않게 줄 단위로만 바꿉니다.
$pattern = '(?m)^\s*elif\s+L\.startswith\([^\)]*\):.*$'
if ($content -match $pattern) {
  $content = [regex]::Replace($content, $pattern, '    elif False:  # hotfix: removed corrupted rule')
  Write-Host "Corrupted elif line neutralized." -ForegroundColor Yellow
} else {
  Write-Host "No corrupted elif line found. (Nothing to patch)" -ForegroundColor Yellow
}

# 2) 파일 상단에 UTF-8 선언 주입(중복 방지)
if ($content -notmatch '(?m)^#\s*-\*-\s*coding:\s*utf-8\s*-\*-') {
  $content = "# -*- coding: utf-8 -*-`r`n" + $content
}

# 3) UTF-8로 저장
Set-Content $main $content -Encoding UTF8

# 4) Git 커밋/푸시
git add -A
git commit -m $CommitMsg
git push origin main

Write-Host "`nHotfix applied. Now go to Render → Environment → 'Save, rebuild and deploy'." -ForegroundColor Green
