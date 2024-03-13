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

# number_of_pages=10

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

# for repo in "${repo_urls[@]}"; do
#   echo "$repo"
#   git clone $repo
#   echo -ne "Клонирование репозитория: [${repo}}]\r"
# done
# echo -ne "\n"

clone-mirror() {
  local url
  url=$1
  local repo_name
  repo_name=$(basename "$url" .git)

  git clone --mirror "$url" "./$repo_name/.git"
  (
    cd "$repo_name" || exit 1
    git config --bool core.bare false
    git reset --hard
  )
}


mkdir ./target
cd ./target || exit 1
# Инициализация счетчика
counter=1
total=${#repo_urls[@]}

for repo in "${repo_urls[@]}"; do
 echo -ne "\r\033[K"
 echo -ne "Клонирование репозитория: [$counter/$total] $repo\r"
 # Используем перенаправление вывода для скрытия стандартного вывода git clone
 # И показываем только ошибки, перенаправляя stderr в stdout
#  git clone "$repo" >/dev/null 2>&1
# Клонирование выбранного репозитория
if [[ "$USE_CLONE_ALL_BRANCHES" == "--all" ]]; then
  clone-mirror "$repo" >/dev/null 2>&1
else
  git clone "$repo" >/dev/null 2>&1
fi
 # Проверяем статус выполнения команды
 if [ $? -ne 0 ]; then
    echo "Ошибка при клонировании репозитория: $repo"
 fi
 # Обновляем счетчик
 ((counter++))
#  echo -ne "                                                                                                                    \r"
done

echo -ne "\n"

cd ..

echo "=> Клонирование $total проектов завершено"
exit 0
