#!/usr/bin/env bash
# =====================================================================================
# GuardaRio · reúne as evidências técnicas da entrega. Cada bloco mostra o comando e a saída.
#
# Onde rodar: na VM, na raiz do repositório, com os containers no ar.
# Uso:
#   ./scripts/evidencias.sh                  containers, logs, exec, SELECT, volume e rede
#   ./scripts/evidencias.sh --persistencia   derruba e sobe os containers e mostra que os dados ficaram
# =====================================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

do_env() { [ -f .env ] && grep -E "^$1=" .env | head -n1 | cut -d= -f2- || true; }
POSTGRES_USER="$(do_env POSTGRES_USER)"; POSTGRES_USER="${POSTGRES_USER:-guardario}"
POSTGRES_DB="$(do_env POSTGRES_DB)";     POSTGRES_DB="${POSTGRES_DB:-guardario}"

titulo() { printf '\n\n########## %s ##########\n' "$1"; }
# Mostra o comando como ele seria digitado e depois executa
rodar() { printf '\n$ %s\n' "$1"; eval "$1"; }
PSQL="docker exec guardario-db psql -U $POSTGRES_USER -d $POSTGRES_DB -c"

SQL_AREAS="SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco ORDER BY id;"
SQL_ABRIGOS="SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area FROM abrigo a JOIN area_risco r ON r.id = a.area_id ORDER BY a.id;"
SQL_FK="SELECT conname AS chave_estrangeira, conrelid::regclass AS tabela, confrelid::regclass AS referencia FROM pg_constraint WHERE contype = 'f' AND conrelid = 'abrigo'::regclass;"

esperar_api() {
  printf '\nEsperando a API ficar healthy'
  for _ in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' guardario-api 2>/dev/null)" = "healthy" ] && { echo " ok"; return 0; }
    printf '.'; sleep 3
  done
  echo " não ficou healthy em 3 minutos"; return 1
}

if [ "${1:-}" = "--persistencia" ]; then
  titulo "PERSISTÊNCIA 1/4 · dados antes de derrubar os containers"
  rodar "$PSQL \"$SQL_AREAS\""
  rodar "$PSQL \"$SQL_ABRIGOS\""

  titulo "PERSISTÊNCIA 2/4 · docker compose down (remove os containers e a rede, mantém o volume)"
  rodar "docker compose down"
  rodar "docker ps -a"
  rodar "docker volume ls"

  titulo "PERSISTÊNCIA 3/4 · docker compose up -d (containers novos, mesmo volume)"
  rodar "docker compose up -d"
  esperar_api
  rodar "docker compose ps"

  titulo "PERSISTÊNCIA 4/4 · os mesmos dados, lidos pelos containers novos"
  rodar "$PSQL \"$SQL_AREAS\""
  rodar "$PSQL \"$SQL_ABRIGOS\""
  exit 0
fi

titulo "1 · VM e versões"
rodar "hostname"
rodar "uname -sr"
rodar "docker --version"
rodar "docker compose version"

titulo "2 · Containers em execução, em background"
rodar "docker compose ps"

titulo "3 · Logs dos containers"
rodar "docker compose logs --tail=25 api"
rodar "docker compose logs --tail=15 db"

titulo "4 · Acesso ao container da aplicação: usuário, diretório e arquivos"
rodar "docker exec guardario-api sh -c 'whoami; id; pwd; ls -la'"
rodar "docker exec guardario-api ps -o pid,user,args"

titulo "5 · Acesso ao container do banco: usuário e diretório dos dados"
rodar "docker exec guardario-db sh -c 'whoami; id; ls -ld /var/lib/postgresql/data'"
rodar "docker exec guardario-db sh -c 'ps -o pid,user,args | head -n 4'"

titulo "6 · Variáveis de ambiente (os valores das senhas ficam ocultos)"
printf '\n$ docker exec guardario-api env\n'
docker exec guardario-api env \
  | grep -E '^(SPRING_PROFILES_ACTIVE|DB_URL|DB_USERNAME|DB_PASSWORD|JWT_SECRET|ADMIN_EMAIL|ADMIN_PASSWORD|SWAGGER_ENABLED|SEED_ENABLED|PORT|TZ)=' \
  | sed -E 's/^(DB_PASSWORD|JWT_SECRET|ADMIN_PASSWORD)=.*/\1=********/' | sort
printf '\n$ docker exec guardario-db env\n'
docker exec guardario-db env \
  | grep -E '^(POSTGRES_DB|POSTGRES_USER|POSTGRES_PASSWORD|PGDATA|TZ)=' \
  | sed -E 's/^(POSTGRES_PASSWORD)=.*/\1=********/' | sort

titulo "7 · SELECT direto no banco: duas tabelas relacionadas"
rodar "$PSQL '\dt'"
rodar "$PSQL \"$SQL_AREAS\""
rodar "$PSQL \"$SQL_ABRIGOS\""
rodar "$PSQL \"$SQL_FK\""

titulo "8 · Volume nomeado"
rodar "docker volume ls"
rodar "docker volume inspect guardario-pgdata"

titulo "9 · Rede e comunicação entre os containers"
rodar "docker network ls"
printf '\n$ docker network inspect guardario-net   (containers ligados à rede)\n'
docker network inspect guardario-net --format '{{range .Containers}}{{.Name}}  {{.IPv4Address}}{{"\n"}}{{end}}'
# o DNS interno do Docker resolve o nome do serviço, e a API alcança a porta do banco pela rede interna
rodar "docker exec guardario-api getent hosts db"
rodar "docker exec guardario-api nc -zv -w 3 db 5432"
rodar "docker port guardario-api"
rodar "docker port guardario-db"

echo
echo "Evidências reunidas. Para a prova de persistência: ./scripts/evidencias.sh --persistencia"
