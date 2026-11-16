#!/usr/bin/env bash
# GuardaRio · apaga TUDO o que o provisionar-vm.sh criou (VM, disco, rede, NSG e IP).
# Rodar só depois da apresentação: a exclusão não tem volta.
# Uso: ./scripts/remover-recursos.sh
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-guardario}"

echo "Recursos do grupo ${RESOURCE_GROUP}:"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{nome:name, tipo:type}" --output table

read -r -p "Apagar o grupo ${RESOURCE_GROUP} e tudo o que está nele? (digite sim) " RESPOSTA
[ "$RESPOSTA" = "sim" ] || { echo "Nada foi apagado."; exit 0; }

az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo "Exclusão iniciada. Acompanhe com: az group list --output table"
