#!/usr/bin/env bash
# =====================================================================================
# GuardaRio · CRUD completo em duas tabelas relacionadas, chamando a API pela rede.
#   area_risco (1) ──── (N) abrigo      (abrigo.area_id é chave estrangeira de area_risco.id)
#
# Uso:
#   ./scripts/testar-crud.sh http://IP-PUBLICO:8080            cria, lê, altera e apaga
#   ./scripts/testar-crud.sh http://IP-PUBLICO:8080 --manter   cria, lê e altera; deixa os registros
#                                                              no banco (para a prova de persistência)
#
# Login do ADMIN: lido do .env quando o script roda na VM. Fora da VM, informe antes:
#   export ADMIN_EMAIL=... ADMIN_PASSWORD=...
# Rodando na VM, o script mostra também o SELECT direto no PostgreSQL depois de cada operação.
# =====================================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

BASE_URL="${1:-}"
MANTER="${2:-}"
[ -n "$BASE_URL" ] || { echo "Informe o endereço da API. Exemplo: ./scripts/testar-crud.sh http://20.1.2.3:8080"; exit 1; }
BASE_URL="${BASE_URL%/}"

case "$BASE_URL" in
  *localhost*|*127.0.0.1*) echo "AVISO: a entrega pede o IP público da VM, não localhost.";;
esac

# Valor de uma chave do .env, sem executar o arquivo
do_env() { [ -f .env ] && grep -E "^$1=" .env | head -n1 | cut -d= -f2- || true; }

ADMIN_EMAIL="${ADMIN_EMAIL:-$(do_env ADMIN_EMAIL)}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(do_env ADMIN_PASSWORD)}"
[ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ] || { echo "Defina ADMIN_EMAIL e ADMIN_PASSWORD (ou rode na VM, onde está o .env)."; exit 1; }

POSTGRES_USER="$(do_env POSTGRES_USER)"; POSTGRES_USER="${POSTGRES_USER:-guardario}"
POSTGRES_DB="$(do_env POSTGRES_DB)";     POSTGRES_DB="${POSTGRES_DB:-guardario}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TOKEN=""
STATUS=""

# chamar MÉTODO CAMINHO STATUS_ESPERADO [CORPO_JSON]
chamar() {
  local metodo="$1" caminho="$2" esperado="$3" corpo="${4:-}"
  local args=(-sS -X "$metodo" -o "$TMP/corpo" -D "$TMP/cabecalhos" -w '%{http_code}' -H 'Accept: application/json')
  [ -n "$TOKEN" ] && args+=(-H "Authorization: Bearer $TOKEN")
  [ -n "$corpo" ] && args+=(-H 'Content-Type: application/json' -d "$corpo")
  STATUS="$(curl "${args[@]}" "$BASE_URL$caminho")"
  printf '\n>> %s %s  ->  HTTP %s (esperado %s)\n' "$metodo" "$caminho" "$STATUS" "$esperado"
  [ -n "$corpo" ] && printf '   enviado:  %s\n' "$corpo"
  # os _links do HATEOAS saem da tela para sobrar espaço para os dados do recurso
  [ -s "$TMP/corpo" ] && printf '   resposta: %s\n' "$(sed 's/"_links":{.*}},"id"/"id"/' "$TMP/corpo" | head -c 420)"
  if [ "$STATUS" != "$esperado" ]; then
    echo "FALHOU: o status não é o esperado."
    exit 1
  fi
}

# id do recurso criado, tirado do cabeçalho Location do 201
id_criado() { grep -i '^location:' "$TMP/cabecalhos" | tr -d '\r' | sed 's|.*/||'; }

# SELECT direto no banco: só existe quando o script roda na VM, ao lado dos containers
sql() {
  if command -v docker >/dev/null 2>&1 && docker inspect guardario-db >/dev/null 2>&1; then
    printf '\n   SELECT no PostgreSQL (container guardario-db):\n'
    docker exec guardario-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1" | sed 's/^/   /'
  fi
}
SQL_AREAS="SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco ORDER BY id;"
SQL_ABRIGOS="SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area FROM abrigo a JOIN area_risco r ON r.id = a.area_id ORDER BY a.id;"

echo "=== GuardaRio · CRUD em $BASE_URL ==="

# Logo depois do "up -d" a API ainda está subindo: espera até 2 minutos pelo health
printf 'Esperando a API responder'
for _ in $(seq 1 40); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE_URL/actuator/health" || true)" = "200" ] && break
  printf '.'; sleep 3
done
echo

chamar GET /actuator/health 200

echo; echo "--- Login do ADMIN (as escritas exigem token JWT) ---"
# Chamada direta, sem o chamar(): a senha e o token não aparecem na tela nem no vídeo
STATUS="$(curl -sS -o "$TMP/corpo" -w '%{http_code}' -X POST "$BASE_URL/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$ADMIN_EMAIL\",\"senha\":\"$ADMIN_PASSWORD\"}")"
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$TMP/corpo")"
printf '\n>> POST /api/auth/login  ->  HTTP %s (esperado 200)\n' "$STATUS"
[ "$STATUS" = "200" ] && [ -n "$TOKEN" ] || { echo "FALHOU: login recusado. Confira ADMIN_EMAIL e ADMIN_PASSWORD."; head -c 300 "$TMP/corpo"; echo; exit 1; }
echo "   token JWT recebido (${#TOKEN} caracteres), usado no cabeçalho Authorization: Bearer"

echo; echo "--- CREATE ---"
chamar POST /api/areas 201 '{"nome":"Jardim Pantanal","cidade":"São Paulo","uf":"SP","populacaoEstimada":48000,"latitude":-23.4985,"longitude":-46.4290}'
AREA_ID="$(id_criado)"
chamar POST /api/abrigos 201 "{\"nome\":\"EMEF Jardim Pantanal\",\"endereco\":\"Rua Capachós, 120\",\"capacidade\":120,\"ocupacao\":0,\"aceitaPets\":true,\"acessivelPcd\":true,\"telefone\":\"1125550101\",\"areaId\":$AREA_ID}"
ABRIGO_ID="$(id_criado)"
sql "$SQL_AREAS"
sql "$SQL_ABRIGOS"

echo; echo "--- READ ---"
chamar GET "/api/areas/$AREA_ID" 200
chamar GET "/api/abrigos/$ABRIGO_ID" 200

echo; echo "--- UPDATE ---"
chamar PUT "/api/areas/$AREA_ID" 200 '{"nome":"Jardim Pantanal","cidade":"São Paulo","uf":"SP","populacaoEstimada":52000,"latitude":-23.4985,"longitude":-46.4290}'
chamar PUT "/api/abrigos/$ABRIGO_ID" 200 "{\"nome\":\"EMEF Jardim Pantanal (ginásio)\",\"endereco\":\"Rua Capachós, 120\",\"capacidade\":150,\"ocupacao\":0,\"aceitaPets\":true,\"acessivelPcd\":true,\"telefone\":\"1125550101\",\"areaId\":$AREA_ID}"
sql "$SQL_AREAS"
sql "$SQL_ABRIGOS"

if [ "$MANTER" = "--manter" ]; then
  echo
  echo "=== C, R e U concluídos. Área $AREA_ID e abrigo $ABRIGO_ID ficaram no banco (--manter). ==="
  exit 0
fi

echo; echo "--- DELETE ---"
# A área tem um abrigo ligado a ela: a chave estrangeira não deixa apagar o pai antes do filho
chamar DELETE "/api/areas/$AREA_ID" 409
chamar DELETE "/api/abrigos/$ABRIGO_ID" 204
chamar DELETE "/api/areas/$AREA_ID" 204
chamar GET "/api/abrigos/$ABRIGO_ID" 404
chamar GET "/api/areas/$AREA_ID" 404
sql "$SQL_AREAS"
sql "$SQL_ABRIGOS"

echo
echo "=== CRUD completo nas duas tabelas: todos os status conferem. ==="
