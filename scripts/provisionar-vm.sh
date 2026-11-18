#!/usr/bin/env bash
# =====================================================================================
# GuardaRio · provisiona a infraestrutura na Azure só com Azure CLI.
#
# Cria: grupo de recursos, rede virtual + sub-rede, NSG (firewall), IP público fixo
#       e a VM Ubuntu. Libera a porta 22 (SSH) e a 8080 (API) e liga o desligamento
#       automático da VM. Toda a infraestrutura fica neste arquivo: Infraestrutura como Código.
#
# Onde rodar: no seu computador (com a Azure CLI instalada) ou no Azure Cloud Shell.
# Uso:        ./scripts/provisionar-vm.sh
# Sem cota na região ou sem o tamanho da VM? Troque sem editar o arquivo:
#             LOCATION=brazilsouth VM_SIZE=Standard_B2s ./scripts/provisionar-vm.sh
# =====================================================================================
set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-guardario}"
LOCATION="${LOCATION:-northcentralus}"
VM_NAME="${VM_NAME:-vm-guardario}"
VM_SIZE="${VM_SIZE:-Standard_B2als_v2}"     # 2 vCPU e 4 GB: o build do Maven roda dentro da VM
VM_IMAGE="${VM_IMAGE:-Ubuntu2404}"          # Ubuntu Server 24.04 LTS
ADMIN_USER="${ADMIN_USER:-azureuser}"
VNET_NAME="${VNET_NAME:-vnet-guardario}"
SUBNET_NAME="${SUBNET_NAME:-snet-guardario}"
NSG_NAME="${NSG_NAME:-nsg-guardario}"
PUBLIC_IP_NAME="${PUBLIC_IP_NAME:-pip-guardario}"
API_PORT="${API_PORT:-8080}"
# Desligamento automático em UTC: 0230 UTC é 23:30 no horário de Brasília (UTC-3)
SHUTDOWN_UTC="${SHUTDOWN_UTC:-0230}"
# Tags no formato da aula 08 (owner e purpose), além das do projeto
TAGS=(projeto=guardario disciplina=devops owner=GuardaRio purpose=GlobalSolution)

command -v az >/dev/null || { echo "Azure CLI não encontrada. Instale (https://aka.ms/installazurecli) ou use o Azure Cloud Shell."; exit 1; }

echo "==> 1/6 Conta Azure"
az account show --output none 2>/dev/null || az login --output none
az account show --query "{assinatura:name, id:id}" --output table

echo "==> 2/6 Grupo de recursos ${RESOURCE_GROUP} em ${LOCATION}"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags "${TAGS[@]}" \
  --output none

echo "==> 3/6 VM ${VM_NAME} (${VM_IMAGE}, ${VM_SIZE}) com rede, NSG e IP público"
# Login só por chave SSH (sem senha). A chave fica em ~/.ssh/id_rsa; se não existir, a CLI cria.
# O az vm create também cria a rede, a sub-rede, o NSG (já com a regra da porta 22) e o IP público com os nomes abaixo.
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --vnet-name "$VNET_NAME" \
  --vnet-address-prefix 10.0.0.0/16 \
  --subnet "$SUBNET_NAME" \
  --subnet-address-prefix 10.0.0.0/24 \
  --nsg "$NSG_NAME" \
  --nsg-rule SSH \
  --public-ip-address "$PUBLIC_IP_NAME" \
  --public-ip-sku Standard \
  --tags "${TAGS[@]}" \
  --output none

echo "==> 4/6 Porta ${API_PORT} liberada no NSG (entrada da API)"
az vm open-port \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --port "$API_PORT" \
  --priority 1010 \
  --output none

echo "==> 5/6 Desligamento automático todo dia às ${SHUTDOWN_UTC} UTC (23:30 em Brasília com o padrão)"
# Protege o crédito: se alguém esquecer a VM ligada, ela é desligada (desalocada) sozinha
az vm auto-shutdown \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --time "$SHUTDOWN_UTC" \
  --output none

echo "==> 6/6 Resultado"
IP_PUBLICO="$(az vm show --show-details --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query publicIps --output tsv)"

az vm show --show-details --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" \
  --query "{vm:name, estado:powerState, tamanho:hardwareProfile.vmSize, regiao:location, ipPublico:publicIps, ipPrivado:privateIps}" \
  --output table

az network nsg rule list --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
  --query "[].{regra:name, prioridade:priority, porta:destinationPortRange, acesso:access, direcao:direction}" \
  --output table

az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" \
  --query "{owner:tags.owner, purpose:tags.purpose, projeto:tags.projeto}" \
  --output table

cat <<EOF

VM pronta. IP público: ${IP_PUBLICO}

Próximos passos (dentro da VM):
  ssh ${ADMIN_USER}@${IP_PUBLICO}
  git clone https://github.com/Raphael-Sinelli/guardario-devops.git
  cd guardario-devops
  ./scripts/instalar-docker.sh

Depois do "docker compose up -d --build":
  API:     http://${IP_PUBLICO}:${API_PORT}/actuator/health
  Swagger: http://${IP_PUBLICO}:${API_PORT}/swagger-ui/index.html

Para não gastar crédito fora do uso (além do desligamento automático):
  az vm deallocate --resource-group ${RESOURCE_GROUP} --name ${VM_NAME}
  az vm start      --resource-group ${RESOURCE_GROUP} --name ${VM_NAME}
EOF
