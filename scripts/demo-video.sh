#!/usr/bin/env bash
# =====================================================================================
# GuardaRio · roteiro de demonstração para o vídeo de DevOps.
#
# Mostra, cena por cena, a solução rodando em Docker dentro da VM: scripts, Dockerfile,
# Compose, containers, logs, acesso, variáveis, volume, rede, SELECT, CRUD com SELECT
# depois de cada operação e persistência.
# Em cada etapa: limpa a tela e mostra o título; no Enter, digita o comando letra por
# letra e executa esse mesmo comando, ao vivo; no Enter seguinte, vai para a próxima etapa.
# No modo --corrido roda tudo de uma vez, sem Enter e sem limpar a tela: cada etapa abre
# com uma faixa (título, data e hora, máquina) e ocupa exatamente uma tela, para depois
# rolar o terminal de cena em cena.
#
# Onde rodar: na VM, na raiz do repositório, com os containers no ar.
# Uso:
#   ./scripts/demo-video.sh               da cena 4 até o fim, digitação em velocidade humana
#   ./scripts/demo-video.sh --cena 14     começa na cena 14 (para regravar um trecho)
#   ./scripts/demo-video.sh --rapido      digitação rápida, para ensaio
#   ./scripts/demo-video.sh --lento       digitação lenta, para explicar com calma
#   ./scripts/demo-video.sh --corrido     tudo em sequência, no histórico do terminal,
#                                         terminando com a faixa PROVA AO VIVO
#   ./scripts/demo-video.sh --corrido --sem-prova   o mesmo, sem a prova ao vivo no fim
#
# Segurança: o token do ADMIN é obtido em silêncio a partir do .env e fica na variável
# TOKEN; os comandos mostram $TOKEN, nunca o valor. Os registros criados no CRUD e na
# persistência são apagados no fim ou em caso de erro.
# =====================================================================================
set -Eeuo pipefail

cd "$(dirname "$0")/.."

API="http://130.131.61.173:8080"
PRIMEIRA=4
ULTIMA=15
INICIO="$PRIMEIRA"
CPS=30   # caracteres por segundo da digitação
CORRIDO=0
PROVA=1

while [ $# -gt 0 ]; do
  case "$1" in
    --cena)
      INICIO="${2:-}"; shift
      case "$INICIO" in ''|*[!0-9]*) echo "Uso: ./scripts/demo-video.sh [--cena N] [--rapido|--lento]   (N de $PRIMEIRA a $ULTIMA)"; exit 1;; esac
      if [ "$INICIO" -lt "$PRIMEIRA" ] || [ "$INICIO" -gt "$ULTIMA" ]; then
        echo "Cena $INICIO não existe neste script. As cenas vão de $PRIMEIRA a $ULTIMA."; exit 1
      fi;;
    --rapido) CPS=80;;
    --lento)  CPS=20;;
    --corrido) CORRIDO=1;;
    --sem-prova) PROVA=0;;
    *) echo "Opção desconhecida: $1"; echo "Uso: ./scripts/demo-video.sh [--cena N] [--rapido|--lento]"; exit 1;;
  esac
  shift
done

# ----- cores para fundo escuro -----
TIT=$'\e[1;97;44m'; CMD=$'\e[1;33m'; PROMPT=$'\e[1;32m'; OK=$'\e[1;32m'; ERRO=$'\e[1;97;41m'
ENTER=$'\e[0;36m'; NOTA=$'\e[0;37m'; FIM=$'\e[0m'; BARRA=$'\e[1;94m'; NEG=$'\e[1;97m'

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
exec {SONO}<> <(:)   # descritor vazio: o read -t nele serve de pausa curta sem abrir processo

# ----- modo corrido: cada etapa vira um bloco do tamanho exato de uma tela -----
LINHAS_TELA="$(tput lines 2>/dev/null || echo 35)"
COLS_TELA="$(tput cols 2>/dev/null || echo 135)"
BLOCO=0
exec {TELA}>&1 {TELA_ERR}>&2   # guarda a saída original do terminal
abrir_bloco() { exec >"$TMP/bloco" 2>&1; BLOCO=1; }
linhas_do_bloco() {  # linhas que o bloco ocupa na tela, contando as quebras de linha longas
  local LC_ALL=C.UTF-8 n=0 l w
  while IFS= read -r l || [ -n "$l" ]; do
    w=${#l}
    n=$(( n + (w == 0 ? 1 : (w + COLS_TELA - 1) / COLS_TELA) ))
  done < <(sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$TMP/bloco")
  echo "$n"
}
fechar_bloco() {  # devolve a saída ao terminal, mostra o bloco e completa a tela com linhas em branco
  [ "$BLOCO" = 1 ] || return 0
  exec 1>&"$TELA" 2>&"$TELA_ERR"; BLOCO=0
  local n; n="$(linhas_do_bloco)"
  [ -n "${DEMO_LOG:-}" ] && printf '%s %s\n' "$n" "$(sed -n 3p "$TMP/bloco" | sed 's/\x1b\[[0-9;]*m//g')" >> "$DEMO_LOG"
  cat "$TMP/bloco"
  while [ "$n" -lt "$LINHAS_TELA" ]; do echo; n=$((n + 1)); done
}
faixa() {  # faixa fácil de achar rolando: barra, título, data e hora, máquina, barra
  local largura=$(( COLS_TELA < 120 ? COLS_TELA : 120 )) barra
  barra="$(printf '%*s' "$largura" '' | tr ' ' '=')"
  printf '\n%s%s%s\n' "$BARRA" "$barra" "$FIM"
  printf '%s  %s  %s\n' "$TIT" "$1" "$FIM"
  printf '%s  %s · máquina: %s%s\n' "$NEG" "$(date '+%d/%m/%Y %H:%M:%S %Z')" "$(hostname)" "$FIM"
  printf '%s%s%s\n' "$BARRA" "$barra" "$FIM"
}

# ----- apresentação -----
esperar_enter() {  # descarta Enter apertado antes da hora e espera um Enter novo
  while read -r -t 0.05 _ </dev/tty; do :; done
  printf '%s[Enter] %s%s' "$ENTER" "$1" "$FIM"
  read -rs _ </dev/tty
}
titulo() {  # titulo "6" "Dockerfile": limpa a tela, mostra a faixa e espera o Enter que dispara a digitação
  if [ "$CORRIDO" = 1 ]; then
    fechar_bloco; abrir_bloco
    if [ "$1" = "FIM" ]; then faixa "FIM · $2"; else faixa "CENA $1 · $2"; fi
    return 0
  fi
  clear
  local texto="  CENA $1 · $2  "
  [ "$1" = "FIM" ] && texto="  FIM · $2  "
  printf '%s%s%s\n\n' "$TIT" "$texto" "$FIM"
  esperar_enter "digitar o comando"
  printf '\r\e[K'
}
digitar() {  # escreve o comando letra por letra; comando longo sai três vezes mais rápido
  local s="$1" cps="$CPS" i ms
  if [ "$CORRIDO" = 1 ]; then printf '%s$ %s%s%s\n' "$PROMPT" "$CMD" "$s" "$FIM"; return 0; fi
  [ "${#s}" -gt 70 ] && cps=$((CPS * 3))
  printf '%s$ %s' "$PROMPT" "$CMD"
  for ((i = 0; i < ${#s}; i++)); do
    printf '%s' "${s:i:1}"
    ms=$(( 1000 * (70 + RANDOM % 61) / 100 / cps ))   # de 70% a 130% do intervalo médio
    read -r -t "0.$(printf '%03d' "$ms")" -u "$SONO" _ || true
  done
  printf '%s\n' "$FIM"
}
rodar() {  # digita o comando e executa exatamente esse texto
  digitar "$1"
  eval "$1"
}
nota() { printf '%s%s%s\n' "$NOTA" "$1" "$FIM"; }
pausa() { [ "$CORRIDO" = 1 ] && return 0; esperar_enter "próxima etapa"; printf '\n'; }

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
  fechar_bloco
  stty echo </dev/tty 2>/dev/null || true
  apagar_registros; rm -rf "$TMP"
}
falhou() {
  fechar_bloco
  printf '\n%s ERRO na linha %s: a etapa não terminou como esperado. %s\n' "$ERRO" "$1" "$FIM"
  printf '%sOs registros de teste criados por este script foram apagados. Corrija e rode de novo com --cena.%s\n' "$NOTA" "$FIM"
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

# ----- chamada da API pelo IP público -----
# chamar MÉTODO CAMINHO STATUS_ESPERADO [CORPO_JSON]
# Monta o curl, digita esse texto e executa o mesmo texto. A resposta aparece inteira,
# e a última linha (HTTP nnn, do -w do curl) sai em verde ou vermelho.
chamar() {
  local metodo="$1" caminho="$2" esperado="$3" corpo="${4:-}" cmd status
  cmd="curl -s -w '\\nHTTP %{http_code}\\n'"
  [ "$metodo" != "GET" ] && cmd="$cmd -X $metodo"
  cmd="$cmd $API$caminho"
  [ "$metodo" != "GET" ] && cmd="$cmd -H \"Authorization: Bearer \$TOKEN\""
  [ -n "$corpo" ] && cmd="$cmd -H \"Content-Type: application/json\" -d '$corpo'"
  digitar "$cmd"
  eval "$cmd" > "$TMP/saida"
  status="$(tail -n 1 "$TMP/saida" | sed -n 's/^HTTP \([0-9]*\)$/\1/p')"
  sed '$d' "$TMP/saida" | sed '/^$/d'
  if [ "$status" = "$esperado" ]; then
    printf '%sHTTP %s%s\n' "$OK" "$status" "$FIM"
  else
    printf '%s HTTP %s, esperado %s %s\n' "$ERRO" "$status" "$esperado" "$FIM"
    return 1
  fi
}
id_da_resposta() { sed -n 's/.*"id":\([0-9]*\).*/\1/p' "$TMP/saida" | head -n1; }
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
  printf '%sEsperando o serviço api ficar healthy' "$NOTA"
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
  rodar "$PSQL \"$SQL_JOIN\""; pausa

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
  nota "Apagando os registros de teste da persistência:"
  chamar DELETE "/api/abrigos/$ABRIGO" 204; ABRIGO=""
  chamar DELETE "/api/areas/$AREA" 204; AREA=""
  pausa
}

# ================================== execução ==================================

# Enter apertado enquanto um comando roda não vira linha em branco na tela
stty -echo </dev/tty 2>/dev/null || true
carregar_token
for n in $(seq "$INICIO" "$ULTIMA"); do
  "cena$n"
done
titulo "FIM" "Registros de teste apagados: o banco voltou ao estado do começo"
rodar "$PSQL \"$SQL_JOIN\""

# no modo corrido, a prova de que está no ar agora, sempre depois das cenas
if [ "$CORRIDO" = 1 ] && [ "$PROVA" = 1 ]; then
  fechar_bloco; abrir_bloco
  faixa "PROVA AO VIVO · a solução no ar neste momento"
  rodar "docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'"
  echo
  rodar "curl -s -w '\\nHTTP %{http_code}\\n' $API/actuator/health"
  echo
  rodar "curl -s -w '\\nHTTP %{http_code}\\n' $API/api/areas"
fi
fechar_bloco
