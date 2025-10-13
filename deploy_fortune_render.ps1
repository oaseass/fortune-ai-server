<#  deploy_fortune_render.ps1
    - 로컬 폴더를 GitHub 레포에 푸시
    - requirements.txt / Dockerfile / render.yaml / .gitignore 자동 생성(없으면)
    - Render “원클릭 배포” URL 출력(+옵션으로 자동 열기)
#>

param(
  [Parameter(Mandatory=$true)] [string]$ProjectPath,      # 예: C:\fortune_ai_server_pro_lunar
  [Parameter(Mandatory=$true)] [string]$RepoUrl,          # 예: https://github.com/oaseass/fortune-ai-server.git
  [Parameter(Mandatory=$true)] [string]$GitUserName,      # 예: oaseass
  [Parameter(Mandatory=$true)] [string]$GitUserEmail,     # 예: you@example.com
  [switch]$ForceOverwrite,                                # 파일 덮어쓰기 허용
  [switch]$OpenRender                                     # 완료 후 Render 배포 페이지 자동 열기
)

function Fail($msg){ Write-Error $msg; exit 1 }

# 0) 기본 체크
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git이 설치되어 있지 않습니다. https://git-scm.com 에서 설치 후 다시 실행하세요." }
if (-not (Test-Path $ProjectPath)) { Fail "ProjectPath 경로가 없습니다: $ProjectPath" }

Set-Location $ProjectPath

# 유틸: 파일이 없으면 생성, ForceOverwrite면 덮어쓰기
function Write-IfNeeded($Path, $Content){
  if ((Test-Path $Path) -and -not $ForceOverwrite) {
    Write-Host "존재함: $Path (덮어쓰지 않음)" -ForegroundColor Yellow
  } else {
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $Content | Out-File -FilePath $Path -Encoding utf8 -Force
    Write-Host "작성됨: $Path" -ForegroundColor Green
  }
}

# 1) 필수 파일 생성
$requirements = @"
fastapi==0.112.2
uvicorn[standard]==0.30.6
python-multipart==0.0.9
Pillow==10.4.0
opencv-python-headless==4.10.0.84
lunar-python==1.2.24
reportlab==4.2.2
python-dotenv==1.0.1
numpy<2.0
"@
Write-IfNeeded -Path (Join-Path $ProjectPath "requirements.txt") -Content $requirements

$dockerfile = @"
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["sh","-c","uvicorn main:app --host 0.0.0.0 --port \${PORT:-8000}"]
"@
Write-IfNeeded -Path (Join-Path $ProjectPath "Dockerfile") -Content $dockerfile

$renderYaml = @"
services:
  - type: web
    name: fortune-ai-server
    env: docker
    plan: free
    autoDeploy: true
    envVars:
      - key: SERVICE_TOKEN
        sync: false
      - key: ALLOW_ORIGINS
        value: "*"
"@
Write-IfNeeded -Path (Join-Path $ProjectPath "render.yaml") -Content $renderYaml

$gitignore = @"
__pycache__/
*.pyc
.venv/
.env
.DS_Store
Thumbs.db
.vscode/
.idea/
dist/
build/
"@
Write-IfNeeded -Path (Join-Path $ProjectPath ".gitignore") -Content $gitignore

# 2) Git 초기화/설정
if (-not (Test-Path (Join-Path $ProjectPath ".git"))) {
  git init | Out-Null
  Write-Host "Git 저장소 초기화 완료" -ForegroundColor Green
}

# 글로벌 사용자 설정(없으면만)
$curName  = git config --get user.name
$curEmail = git config --get user.email
if (-not $curName)  { git config --global user.name  $GitUserName  }
if (-not $curEmail) { git config --global user.email $GitUserEmail }

# 3) 커밋 & 브랜치
git add . | Out-Null
git rev-parse --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  git commit -m "chore: initial commit for Render deploy" | Out-Null
} else {
  git commit -m "chore: update for Render deploy" | Out-Null
}
git branch -M main | Out-Null

# 4) 원격 연결 & 푸시
git remote remove origin 2>$null
git remote add origin $RepoUrl
git remote -v

git push -u origin main
if ($LASTEXITCODE -ne 0) { Fail "푸시에 실패했습니다. GitHub 권한/토큰 또는 RepoUrl을 확인하세요." }

Write-Host "`n✅ GitHub 푸시 완료: $RepoUrl" -ForegroundColor Green

# 5) Render 원클릭 배포 링크
$deployUrl = "https://render.com/deploy?repo=" + ($RepoUrl -replace '\.git$','')
Write-Host "`n🔗 Render 원클릭 배포 URL:" -NoNewline; Write-Host " $deployUrl" -ForegroundColor Cyan

if ($OpenRender) {
  try { Start-Process $deployUrl } catch { Write-Warning "브라우저 열기 실패: $($_.Exception.Message)" }
}

Write-Host "`n다음 순서:" -ForegroundColor Yellow
Write-Host "  1) 위 링크에서 Web Service 생성 (Free plan 가능)"
Write-Host "  2) Environment Variables 추가:"
Write-Host "      - SERVICE_TOKEN = 프로덕션 토큰(강한 문자열)"
Write-Host "      - ALLOW_ORIGINS = https://네워드프레스도메인  (테스트면 *)"
Write-Host "  3) 배포 후 URL 복사 → 워드프레스 'Fortune AI Bridge'에 API BASE/SERVICE TOKEN 설정"
