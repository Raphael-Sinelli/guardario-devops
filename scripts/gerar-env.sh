#!/usr/bin/env bash
# Cria o .env a partir do .env.example, com senhas e chave JWT aleatórias.
# Uso (na raiz do repositório, dentro da VM):  ./scripts/gerar-env.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo "O arquivo .env já existe e foi mantido. Para gerar outro, apague-o antes: rm .env"
  exit 0
fi

command -v openssl >/dev/null || { echo "openssl não encontrado. Instale com: sudo apt-get install -y openssl"; exit 1; }

# Só letras e números (hexadecimal): não precisa de aspas no .env nem de escape na URL do JDBC.
SENHA_BANCO="$(openssl rand -hex 16)"
CHAVE_JWT="$(openssl rand -hex 32)"
SENHA_ADMIN="Gr@$(openssl rand -hex 6)"

sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${SENHA_BANCO}|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=${CHAVE_JWT}|" \
    -e "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${SENHA_ADMIN}|" \
    .env.example > .env

chmod 600 .env

echo ".env criado (permissão 600, fora do Git)."
echo
echo "  Login do ADMIN na API"
echo "    email: $(grep '^ADMIN_EMAIL=' .env | cut -d= -f2-)"
echo "    senha: ${SENHA_ADMIN}"
echo
echo "Próximo passo: docker compose up -d --build"
