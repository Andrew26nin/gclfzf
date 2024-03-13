#!/bin/bash

# Переменная наличия флага --all
USE_CLONE_ALL_BRANCHES="$1"

# Функция для проверки и установки переменных окружения
setup_env_vars() {
  local var_name
  var_name="$1"
  local value
  value=$(printenv "$var_name")

  if [[ -z "$value" ]]; then
    echo "Переменная окружения $var_name не найдена."
    read -p "Введите значение для $var_name: " value
    if [[ -z "$value" ]]; then
      echo "Значение не может быть пустым. Скрипт завершается."
      exit 1
    fi
    export "$var_name"="$value"
  fi
}

# Вызов функции для проверки и установки переменных окружения
setup_env_vars "GL_DOMAIN"
setup_env_vars "GL_TOKEN"
GL_URL="$GL_DOMAIN//api/v4/projects"

# Функция для проверки наличия команды
check_command() {
  local command_name="$1"
  if ! command -v "$command_name" &>/dev/null; then
    echo "$command_name не найден. Установите $command_name и повторите."
    exit 1
  fi
}

# Вызов функции для проверки наличия jq
check_command "jq"
# Вызов функции для проверки наличия fzf
check_command "fzf"
# Вызов функции для проверки наличия curl
check_command "curl"

echo "==> Получение количества страниц с репозиториями GitLab..."
number_of_pages=$(curl -m 10 -s --head --header "PRIVATE-TOKEN: $GL_TOKEN" "$GL_URL" |
  grep -i x-total-pages | awk '{print $2}' | tr -d '\r\n')

number_of_pages=2

if [[ -z "$number_of_pages" ]]; then
  echo "Не удалось получить данные с {$GL_DOMAIN}. Команда завершается."
  exit 1
fi
# Инициализация массива для хранения URL-ов репозиториев
declare -a repo_urls

# Заполнение массива URL-ами репозиториев
for page in $(seq 1 "$number_of_pages"); do
  # shellcheck disable=SC2207
  repo_urls+=($(curl -m 30 -s --header "PRIVATE-TOKEN: $GL_TOKEN" "$GL_URL?page=$page" |
    jq -r '.[] | "\(.ssh_url_to_repo)"'))
  # Вывод прогресс-бара
  echo -ne "Заполнение массива: [${page}/${number_of_pages}]\r"
done
echo -ne "\n"

for repo in "${repo_urls[@]}"; do
  echo "$repo"
  git clone $repo
done
