function Setup-EnvVars {
    param (
        [string]$VarName
    )

    $value = [System.Environment]::GetEnvironmentVariable($VarName)

    if ([string]::IsNullOrEmpty($value)) {
        $value = Read-Host -Prompt "Введите значение для $VarName"
        if ([string]::IsNullOrEmpty($value)) {
            Write-Host "Значение не может быть пустым. Скрипт завершается."
            exit 1
        }
        [System.Environment]::SetEnvironmentVariable($VarName, $value)
    }
}

# Вызов функции для проверки и установки переменных окружения
Setup-EnvVars -VarName "GL_DOMAIN"
Setup-EnvVars -VarName "GL_TOKEN"
$GL_URL = "$env:GL_DOMAIN//api/v4/projects"

function Check-Command {
    param (
        [string]$CommandName
    )

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        Write-Host "$CommandName не найден. Установите $CommandName и повторите."
        exit 1
    }
}

# Вызов функции для проверки наличия jq
Check-Command -CommandName "jq"
# Вызов функции для проверки наличия fzf
Check-Command -CommandName "fzf"
# Вызов функции для проверки наличия curl
Check-Command -CommandName "curl"

Write-Host "==> Получение количества страниц с репозиториями GitLab..."
$numberOfPages = Invoke-WebRequest -Uri $GL_URL -Method Head -Headers @{"PRIVATE-TOKEN" = $GL_TOKEN} -TimeoutSec 10 |
 Select-String -Pattern "x-total-pages" |
 ForEach-Object { $_.Matches.Groups[1].Value } |
 Trim

if ([string]::IsNullOrEmpty($numberOfPages)) {
 Write-Host "Не удалось получить данные с {$GL_DOMAIN}. Команда завершается."
 exit 1
}


# Инициализация массива для хранения URL-ов репозиториев
$repoUrls = @()

# Заполнение массива URL-ами репозиториев
for ($page = 1; $page -le $numberOfPages; $page++) {
    $response = Invoke-WebRequest -Uri "$GL_URL?page=$page" -Method Get -Headers @{"PRIVATE-TOKEN" = $GL_TOKEN} -TimeoutSec 30
    $repoData = $response.Content | ConvertFrom-Json
    foreach ($repo in $repoData) {
        $repoUrls += "$($repo.name) -> $($repo.ssh_url_to_repo)"
    }
    Write-Progress -Activity "Заполнение массива" -Status "$page/$numberOfPages" -PercentComplete (($page / $numberOfPages) * 100)
}
Write-Host "`n"

# Передача массива в fzf для выбора
# В PowerShell нет прямого аналога fzf, но вы можете использовать Out-GridView для выбора элемента из списка
$selectedRepo = $repoUrls | Out-GridView -Title "Выберите репозиторий" -OutputMode Single


# Вывод выбранного репозитория
Write-Host "Выбранный репозиторий: $selectedRepo"

# Разделение выбранного репозитория на имя и URL
$repoParts = $selectedRepo -split ' -> '
$repoName = $repoParts[0]
$repoUrl = $repoParts[1]

if ([string]::IsNullOrEmpty($repoUrl)) {
    Write-Host "==> URL пустой. Команда завершена."
    exit 1
}

function Clone-Mirror {
    param (
        [string]$Url
    )

    $repoName = Split-Path -Path $Url -Leaf
    $repoName = $repoName -replace '\.git$', ''

    git clone --mirror $Url "./$repoName/.git"
    Set-Location -Path $repoName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Не удалось перейти в директорию $repoName. Команда завершена."
        exit 1
    }
    git config --bool core.bare false
    git reset --hard
    Set-Location -Path ..
}

if ($USE_CLONE_ALL_BRANCHES -eq "--all") {
    Write-Host "Клонирование репозитория $repoName со всеми ветками..."
    Clone-Mirror -Url $repoUrl
} else {
    Write-Host "Клонирование репозитория $repoName..."
    git clone $repoUrl
}

Write-Host "=> Клонирование завершено"
exit 0