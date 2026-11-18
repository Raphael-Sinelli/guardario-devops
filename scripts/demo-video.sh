#!/usr/bin/env bash
# =====================================================================================
# GuardaRio · roteiro de demonstração para o vídeo de DevOps.
#
# Mostra, cena por cena, a solução rodando em Docker dentro da VM: scripts, Dockerfile,
# Compose, containers, logs, acesso, variáveis, volume, rede, SELECT, CRUD com SELECT
# depois de cada operação e persistência. Em cada etapa: limpa a tela, mostra o título
# e o comando, executa e espera Enter.
#
# Onde rodar: na VM, na raiz do repositório, com os containers no ar.
# Uso:
#   ./scripts/demo-video.sh             da cena 4 até o fim
#   ./scripts/demo-video.sh --cena 14   começa na cena 14 (para regravar um trecho)
#
# Segurança: o token do ADMIN é obtido em silêncio a partir do .env e nunca é mostrado.
# Os registros criados no CRUD e na persistência são apagados no fim ou em caso de erro.
# =====================================================================================
set -Eeuo pipefail

cd "$(dirname "$0")/.."

API="http://130.131.61.173:8080"
PRIMEIRA=4
ULTIMA=15
INICIO="$PRIMEIRA"

if [ "${1:-}" = "--cena" ]; then
  INICIO="${2:-}"
  case "$INICIO" in ''|*[!0-9]*) echo "Uso: ./scripts/demo-video.sh --cena N   (N de $PRIMEIRA a $ULTIMA)"; exit 1;; esac
  if [ "$INICIO" -lt "$PRIMEIRA" ] || [ "$INICIO" -gt "$ULTIMA" ]; then
    echo "Cena $INICIO não existe neste script. As cenas vão de $PRIMEIRA a $ULTIMA."; exit 1
  fi
fi

# ----- cores para fundo escuro -----
TIT=$'\e[1;97;44m'; CMD=$'\e[1;33m'; PROMPT=$'\e[1;32m'; OK=$'\e[1;32m'; ERRO=$'\e[1;97;41m'
INFO=$'\e[0;36m'; NEG=$'\e[1m'; FIM=$'\e[0m'

do_env() { [ -f .env ] && grep -E "^$1=" .env | head -n1 | cut -d= -f2- || true; }
POSTGRES_USER="$(do_env POSTGRES_USER)"; POSTGRES_USER="${POSTGRES_USER:-guardario}"
POSTGRES_DB="$(do_env POSTGRES_DB)";     POSTGRES_DB="${POSTGRES_DB:-guardario}"
PSQL="docker exec guardario-db psql -U $POSTGRES_USER -d $POSTGRES_DB -P pager=off -c"
SQL_AREA="SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco ORDER BY id;"
SQL_JOIN="SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area FROM abrigo a JOIN area_risco r ON r.id = a.area_id ORDER BY a.id;"

# ids criados por este script, para a limpeza
AREA=""; ABRIGO=""
TMP="$(mktemp -d)"
TOKEN=""

# ----- apresentação -----
titulo() {  # titulo "6" "Dockerfile"
  clear
  local texto="  CENA $1 · $2  "
  [ "$1" = "FIM" ] && texto="  FIM · $2  "
  printf '%s%s%s\n\n' "$TIT" "$texto" "$FIM"
}
rodar() {  # mostra o comando com "$ " na frente e executa
  printf '%s$ %s%s%s\n' "$PROMPT" "$CMD" "$1" "$FIM"
  eval "$1"
}
nota() { printf '%s%s%s\n' "$INFO" "$1" "$FIM"; }
pausa() {  # descarta Enter apertado antes da hora, para não pular etapa
  while read -r -t 0.05 _ </dev/tty; do :; done
  printf '\n%s[Enter] próxima etapa%s' "$INFO" "$FIM"; read -r _ </dev/tty
}

# ----- limpeza e erro -----
apagar_registros() {
  [ -n "$TOKEN" ] || return 0
  [ -n "$AREA$ABRIGO" ] || return 0
  # se o erro foi no meio da persistência, sobe os containers de novo antes de apagar
  if [ "$(docker inspect -f '{{.State.Health.Status}}' guardario-api 2>/dev/null || true)" != "healthy" ]; then
    docker compose up -d >/dev/null 2>&1 || true
    esperar_api >/dev/null 2>&1 || true
  fi
  if [ -n "$ABRIGO" ]; then
    curl -s -o /dev/null -X DELETE "$API/api/abrigos/$ABRIGO" -H "Authorization: Bearer $TOKEN" || true
    ABRIGO=""
  fi
  if [ -n "$AREA" ]; then
    curl -s -o /dev/null -X DELETE "$API/api/areas/$AREA" -H "Authorization: Bearer $TOKEN" || true
    AREA=""
  fi
}
sair() {
  # a limpeza não pode ser interrompida por um segundo sinal nem pelo trap de erro
  trap '' HUP TERM INT; trap - ERR
  apagar_registros; rm -rf "$TMP"
}
falhou() {
  printf '\n%s ERRO na linha %s: a etapa não terminou como esperado. %s\n' "$ERRO" "$1" "$FIM"
  printf '%sOs registros de teste criados por este script foram apagados. Corrija e rode de novo com --cena.%s\n' "$INFO" "$FIM"
  exit 1
}
trap sair EXIT
trap 'falhou $LINENO' ERR
trap 'printf "\n"; exit 130' INT
# janela fechada ou SSH caído: sai pelo trap EXIT, que apaga os registros de teste
trap 'exit 129' HUP
trap 'exit 143' TERM

# ----- token do ADMIN, em silêncio -----
carregar_token() {
  local email senha corpo
  email="$(do_env ADMIN_EMAIL)"; senha="$(do_env ADMIN_PASSWORD)"
  [ -n "$email" ] && [ -n "$senha" ] || { printf '%s Falta ADMIN_EMAIL ou ADMIN_PASSWORD no .env %s\n' "$ERRO" "$FIM"; exit 1; }
  corpo="$(printf '{"email":"%s","senha":"%s"}' "$email" "$senha")"
  TOKEN="$(printf '%s' "$corpo" | curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' --data-binary @- \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  unset senha corpo
  [ -n "$TOKEN" ] || { printf '%s Login do ADMIN recusado pela API em %s %s\n' "$ERRO" "$API" "$FIM"; exit 1; }
}

# ----- chamada da API: mostra método, URL, corpo, status e resposta -----
# chamar MÉTODO CAMINHO STATUS_ESPERADO [CORPO_JSON]
chamar() {
  local metodo="$1" caminho="$2" esperado="$3" corpo="${4:-}" status mostrar
  mostrar="curl -X $metodo $API$caminho"
  [ "$metodo" != "GET" ] && mostrar="$mostrar -H \"Authorization: Bearer \$TOKEN\""
  [ -n "$corpo" ] && mostrar="$mostrar -d '$corpo'"
  printf '%s$ %s%s%s\n' "$PROMPT" "$CMD" "$mostrar" "$FIM"
  local args=(-s -o "$TMP/corpo" -w '%{http_code}' -X "$metodo" -H 'Accept: application/json')
  [ "$metodo" != "GET" ] && args+=(-H "Authorization: Bearer $TOKEN")
  if [ -n "$corpo" ]; then
    status="$(printf '%s' "$corpo" | curl "${args[@]}" -H 'Content-Type: application/json; charset=utf-8' --data-binary @- "$API$caminho")"
  else
    status="$(curl "${args[@]}" "$API$caminho")"
  fi
  if [ "$status" = "$esperado" ]; then
    printf '%sHTTP %s%s\n' "$OK" "$status" "$FIM"
  else
    printf '%s HTTP %s, esperado %s %s\n' "$ERRO" "$status" "$esperado" "$FIM"
  fi
  # a resposta sem os _links do HATEOAS, para caber na tela
  [ -s "$TMP/corpo" ] && printf '%s\n' "$(sed 's/"_links":{.*}},"id"/"id"/' "$TMP/corpo" | cut -c1-400)"
  [ "$status" = "$esperado" ] || return 1
}
id_da_resposta() { sed -n 's/.*"id":\([0-9]*\).*/\1/p' "$TMP/corpo" | head -n1; }
select_area() { echo; rodar "$PSQL \"$SQL_AREA\""; }
select_join() { echo; rodar "$PSQL \"$SQL_JOIN\""; }

# ================================== cenas ==================================

cena4() {
  titulo 4 "SSH: dentro da VM, Docker e Compose instalados"
  rodar "hostname"
  rodar "grep PRETTY_NAME /etc/os-release"
  rodar "docker --version"
  rodar "docker compose version"
  rodar "pwd"
  pausa
}

cena5() {
  titulo 5 "Scripts do repositório"
  rodar "ls -l scripts/"
  echo
  rodar "grep -m1 -H -E '^# (GuardaRio|Cria)' scripts/*.sh"
  pausa
}

cena6() {
  titulo 6 "Dockerfile: imagem em dois estágios, usuário não root"
  rodar "grep -n -E '^(FROM|WORKDIR|USER|ENV|EXPOSE|HEALTHCHECK|ENTRYPOINT)|adduser' Dockerfile"
  echo
  rodar "docker history guardario-api:1.0.0 --format 'table {{.CreatedBy}}\t{{.Size}}' | sed -n 1,10p"
  echo
  nota "Camadas da imagem com senha, segredo, token ou ARG:"
  rodar "docker history --no-trunc guardario-api:1.0.0 | grep -c -i -E 'password|secret|senha|token|ARG ' || true"
  pausa
}

cena7() {
  titulo 7 "docker-compose.yml: serviços, rede, volume, portas e dependência"
  rodar "grep -n -E '^  [a-z]+:$|image:|container_name|user:|DB_PORT|8080\\}:8080|pgdata|guardario-net|condition|restart:' docker-compose.yml"
  pausa
}

cena8() {
  titulo 8 "Containers em background e processos de cada serviço"
  rodar "docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
  echo
  rodar "docker compose top | sed -n 1,9p"
  pausa
}

cena9() {
  titulo 9 "Logs dos containers"
  rodar "docker compose logs api | grep -E 'Database JDBC URL|Tomcat started|Started GuardaRioApplication' | tail -n 3"
  echo
  rodar "docker compose logs --tail=6 db"
  pausa
}

cena10() {
  titulo 10 "Acesso aos containers: usuário e estrutura de diretórios"
  rodar "docker exec guardario-api sh -c 'whoami; id; pwd; ls -la'"
  echo
  rodar "docker exec guardario-db sh -c 'whoami; id; ls -ld /var/lib/postgresql/data'"
  pausa
}

cena11() {
  titulo 11 "Variáveis de ambiente (sem senhas) e portas"
  rodar "docker exec guardario-api env | grep -E '^(SPRING_PROFILES_ACTIVE|DB_URL|DB_USERNAME|PORT|SEED_ENABLED|SWAGGER_ENABLED|TZ)=' | sort"
  echo
  rodar "docker exec guardario-db env | grep -E '^(POSTGRES_DB|POSTGRES_USER|PGDATA|TZ)=' | sort"
  echo
  rodar "docker port guardario-api"
  rodar "docker port guardario-db"
  pausa
}

cena12() {
  titulo 12 "Volume nomeado e rede bridge"
  rodar "docker volume ls"
  rodar "docker volume inspect guardario-pgdata --format 'Nome: {{.Name}}  Driver: {{.Driver}}  Montado em: {{.Mountpoint}}'"
  echo
  rodar "docker network inspect guardario-net --format 'Driver: {{.Driver}}{{println}}{{range .Containers}}{{.Name}}  {{.IPv4Address}}{{println}}{{end}}'"
  rodar "docker exec guardario-api getent hosts db"
  rodar "docker exec guardario-api nc -zv -w 3 db 5432 2>&1"
  pausa
}

cena13() {
  titulo 13 "SELECT direto no banco: duas tabelas relacionadas"
  rodar "$PSQL '\\dt'"
  rodar "$PSQL \"$SQL_JOIN\""
  rodar "docker exec guardario-db psql -U $POSTGRES_USER -d $POSTGRES_DB -P pager=off -c '\\d abrigo' | tail -n 3"
  pausa
}

cena14() {
  local sub=1
  passo() { titulo "14.$sub" "CRUD pelo IP público · $1"; sub=$((sub + 1)); }

  passo "Create área + SELECT"
  chamar POST /api/areas 201 '{"nome":"Jardim Romano","cidade":"São Paulo","uf":"SP","populacaoEstimada":48000}'
  AREA="$(id_da_resposta)"
  select_area; pausa

  passo "Create abrigo + SELECT com JOIN"
  chamar POST /api/abrigos 201 "{\"nome\":\"CEU Jardim Romano\",\"endereco\":\"Rua das Palmeiras, 120\",\"capacidade\":120,\"aceitaPets\":true,\"acessivelPcd\":true,\"areaId\":$AREA}"
  ABRIGO="$(id_da_resposta)"
  select_join; pausa

  passo "Read área + SELECT"
  chamar GET "/api/areas/$AREA" 200
  echo; rodar "$PSQL \"SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco WHERE id = $AREA;\""
  pausa

  passo "Read abrigo + SELECT"
  chamar GET "/api/abrigos/$ABRIGO" 200
  echo; rodar "$PSQL \"SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area FROM abrigo a JOIN area_risco r ON r.id = a.area_id WHERE a.id = $ABRIGO;\""
  pausa

  passo "Update área + SELECT"
  chamar PUT "/api/areas/$AREA" 200 '{"nome":"Jardim Romano","cidade":"São Paulo","uf":"SP","populacaoEstimada":51000}'
  select_area; pausa

  passo "Update abrigo + SELECT com JOIN"
  chamar PUT "/api/abrigos/$ABRIGO" 200 "{\"nome\":\"CEU Jardim Romano (quadra)\",\"endereco\":\"Rua das Palmeiras, 120\",\"capacidade\":180,\"aceitaPets\":true,\"acessivelPcd\":true,\"areaId\":$AREA}"
  select_join; pausa

  passo "Delete da área que tem abrigo (409) + SELECT"
  chamar DELETE "/api/areas/$AREA" 409
  select_area; select_join; pausa

  passo "Delete abrigo (204) + SELECT"
  chamar DELETE "/api/abrigos/$ABRIGO" 204
  ABRIGO=""
  select_join; pausa

  passo "Delete área (204) + SELECT"
  chamar DELETE "/api/areas/$AREA" 204
  local apagada="$AREA"; AREA=""
  select_area; pausa

  passo "Read da área apagada (404)"
  chamar GET "/api/areas/$apagada" 404
  pausa
}

esperar_api() {
  printf '%sEsperando o serviço api ficar healthy' "$INFO"
  for _ in $(seq 1 60); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' guardario-api 2>/dev/null || true)" = "healthy" ]; then
      printf ' ok%s\n' "$FIM"; return 0
    fi
    printf '.'; sleep 3
  done
  printf '%s\n' "$FIM"; return 1
}

cena15() {
  titulo "15.1" "Persistência · registros de teste e os dados antes"
  chamar POST /api/areas 201 '{"nome":"Vila Itaim","cidade":"São Paulo","uf":"SP","populacaoEstimada":22000}'
  AREA="$(id_da_resposta)"
  chamar POST /api/abrigos 201 "{\"nome\":\"Ginásio Vila Itaim\",\"endereco\":\"Rua Ererê, 50\",\"capacidade\":80,\"aceitaPets\":true,\"acessivelPcd\":true,\"areaId\":$AREA}"
  ABRIGO="$(id_da_resposta)"
  select_join; pausa

  titulo "15.2" "Persistência · docker compose down"
  rodar "docker compose --progress plain down"
  echo
  rodar "docker ps -a"
  rodar "docker volume ls"
  pausa

  titulo "15.3" "Persistência · docker compose up -d"
  rodar "docker compose --progress plain up -d"
  esperar_api
  rodar "docker compose ps --format 'table {{.Name}}\t{{.Status}}'"
  pausa

  titulo "15.4" "Persistência · os mesmos dados nos containers novos"
  select_join
  echo
  nota "Apagando os registros de teste da persistência..."
  chamar DELETE "/api/abrigos/$ABRIGO" 204; ABRIGO=""
  chamar DELETE "/api/areas/$AREA" 204; AREA=""
  pausa
}

# ================================== execução ==================================

carregar_token
for n in $(seq "$INICIO" "$ULTIMA"); do
  "cena$n"
done
titulo "FIM" "Registros de teste apagados: o banco voltou ao estado do começo"
rodar "$PSQL \"$SQL_JOIN\""
