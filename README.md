# GuardaRio · DevOps Tools & Cloud Computing

**Global Solution 2026/2 · FIAP · CitizenTech**

Este repositório coloca a solução GuardaRio na nuvem. A **API Java (Spring Boot) e o PostgreSQL rodam em dois containers Docker, orquestrados por Docker Compose, dentro de uma VM do Microsoft Azure criada por Azure CLI**. Quem usa a solução chega pelo IP público da VM.

| | |
|---|---|
| Aplicação na VM Azure | http://130.131.61.173:8080/swagger-ui/index.html (a VM fica desligada fora das demonstrações; para religar, veja [Desligar e religar a VM](#desligar-e-religar-a-vm)) |
| Vídeo da demonstração | **A PREENCHER** (link do YouTube, não listado) |
| Código da API | pasta [`api/`](api/), a mesma API da entrega de Java Advanced ([guardario-api](https://github.com/Raphael-Sinelli/guardario-api)) |

## Integrantes

| Nome | RM | Turma |
|---|---|---|
| Henrique Spoltore Moreno Pavão dos Santos | RM568130 | 2TDSPS |
| Raphael Oliveira Sinelli Mendonça | RM568346 | 2TDSPS |
| Arthur Lins Belarmino | RM566845 | 2TDSPA |

## Sumário

* [A solução e o tema CitizenTech](#a-solução-e-o-tema-citizentech)
* [Arquitetura macro](#arquitetura-macro)
* [O que tem neste repositório](#o-que-tem-neste-repositório)
* [Onde está cada requisito](#onde-está-cada-requisito)
* [How To: do zero até o CRUD na nuvem](#how-to-do-zero-até-o-crud-na-nuvem)
  * [1. Provisionar a VM com Azure CLI](#1-provisionar-a-vm-com-azure-cli)
  * [2. Instalar o Docker dentro da VM](#2-instalar-o-docker-dentro-da-vm)
  * [3. Subir os containers com Docker Compose](#3-subir-os-containers-com-docker-compose)
  * [4. CRUD pelo IP público, com SELECT depois de cada operação](#4-crud-pelo-ip-público-com-select-depois-de-cada-operação)
  * [5. SELECT direto no banco](#5-select-direto-no-banco)
  * [6. Persistência dos dados](#6-persistência-dos-dados)
* [Evidências](#evidências)
* [Dockerfile explicado](#dockerfile-explicado)
* [Docker Compose explicado](#docker-compose-explicado)
* [Variáveis de ambiente](#variáveis-de-ambiente)
* [Operação do dia a dia](#operação-do-dia-a-dia)
* [Segurança](#segurança)
* [Problemas comuns](#problemas-comuns)
* [Uso de IA generativa](#uso-de-ia-generativa)

## A solução e o tema CitizenTech

O GuardaRio é uma CitizenTech de alerta antecipado de enchentes para moradores de áreas ribeirinhas e de baixada.

**O problema.** O alerta oficial cobre a cidade ou a bacia, e o morador da rua mais baixa não sabe se a água vai chegar à casa dele nem quando. Na cheia cai a energia e a rede de celular. Famílias chegam a abrigos lotados, sem acessibilidade ou que não aceitam animais. Os pedidos de socorro chegam por grupos de WhatsApp e ligações, sem ordem de prioridade.

**Para quem.** Moradores de áreas de risco, como a Dona Cida, persona do grupo: 67 anos, moradora do Jardim Pantanal, às margens do Tietê, com o neto e uma cadela, sem carro. E a Defesa Civil, que atende os relatos e cuida dos abrigos.

**Como funciona.** Estações IoT medem o nível do rio e a chuva, classificam o risco no próprio dispositivo e acionam uma sirene local mesmo sem internet. As leituras chegam à API na nuvem, que gera alertas automáticos para a área, mostra no app os abrigos com vaga (acessíveis e que aceitam pets) e recebe os relatos dos moradores com prioridade calculada.

A API desta entrega é essa API da nuvem: é ela que roda no container `guardario-api`, e o banco dela é o container `guardario-db`. O projeto se liga aos ODS 11 (cidades sustentáveis), 13 (ação climática), 3 (saúde e bem-estar), 10 (redução das desigualdades) e 9 (infraestrutura resiliente).

## Arquitetura macro

![Arquitetura macro do GuardaRio na Azure](docs/arquitetura.png)

O morador (app), o agente da Defesa Civil (Swagger) e a ponte das estações IoT chegam pela internet ao IP público da VM, na porta 8080. O NSG da Azure só deixa entrar a 22 (SSH) e a 8080 (API). Dentro da VM, o Docker Compose mantém dois containers na rede `guardario-net`: a API fala com o banco pelo nome `db`, e o banco grava no volume nomeado `guardario-pgdata`.

| Recurso | Nome | Detalhe |
|---|---|---|
| Grupo de recursos | `rg-guardario` | região `northcentralus` |
| Rede virtual e sub-rede | `vnet-guardario` / `snet-guardario` | `10.0.0.0/16` e `10.0.0.0/24` |
| Firewall (NSG) | `nsg-guardario` | entrada: TCP 22 e TCP 8080 |
| IP público | `pip-guardario` | `130.131.61.173`, SKU Standard, fixo |
| Máquina virtual | `vm-guardario` | Ubuntu Server 24.04 LTS, `Standard_B2als_v2` (2 vCPU, 4 GB) |
| Rede Docker | `guardario-net` | bridge |
| Container da aplicação | `guardario-api` | imagem `guardario-api:1.0.0`, porta `8080:8080`, usuário `guardario` |
| Container do banco | `guardario-db` | imagem `postgres:16-alpine`, porta `127.0.0.1:5432:5432`, usuário `postgres` |
| Volume nomeado | `guardario-pgdata` | montado em `/var/lib/postgresql/data` |
| Rede bridge entre os serviços | `guardario-net`, driver `bridge`; a API acha o banco pelo nome do serviço `db` | [`docker-compose.yml`](docker-compose.yml) | [18](docs/evidencias/18-rede-guardario-net.png) |

A VM é IaaS: a Azure entrega a máquina virtual, a rede e o disco, e nós cuidamos do sistema operacional, do Docker e da aplicação. A região e o tamanho foram escolhidos consultando o `az vm list-skus`, como na aula 08: a assinatura Azure da FIAP só permite cinco regiões, e em `brazilsouth` os tamanhos de VM que consultamos aparecem como `NotAvailableForSubscription`, enquanto em `northcentralus` o `Standard_B2als_v2` aparece sem restrição:

```bash
az vm list-skus --location northcentralus --resource-type virtualMachines --size Standard_B2 -o table
```

O arquivo editável do diagrama é o [`docs/arquitetura.svg`](docs/arquitetura.svg).

## O que tem neste repositório

```
guardario-devops/
├── Dockerfile               imagem da API em dois estágios (build com JDK, execução com JRE)
├── docker-compose.yml       serviços api e db, rede, volume, portas, variáveis e dependência
├── .dockerignore            só o código da API entra no build
├── .env.example             modelo das variáveis de ambiente (o .env não vai para o Git)
├── api/                     código-fonte da API Java 21 + Spring Boot 4 (com o README dela)
├── scripts/
│   ├── provisionar-vm.sh    Azure CLI: grupo de recursos, rede, NSG, IP público e VM
│   ├── instalar-docker.sh   Docker Engine e Docker Compose dentro da VM
│   ├── gerar-env.sh         cria o .env com senhas e chave JWT aleatórias
│   ├── testar-crud.sh       CRUD completo em duas tabelas relacionadas, pelo IP público
│   ├── evidencias.sh        containers, logs, exec, SELECT, volume, rede e persistência
│   ├── demo-video.sh        roteiro de demonstração do vídeo: digita e executa cada comando, Enter entre as etapas
│   └── remover-recursos.sh  apaga o grupo de recursos depois da apresentação
└── docs/
    ├── arquitetura.png      arquitetura macro (e o .svg editável)
    └── evidencias/          prints reais da VM e, em texto/, as saídas completas
```

## Onde está cada requisito

Cada requisito das páginas 37 e 38 do enunciado, com o arquivo que o implementa e o print que comprova. Os prints estão na seção [Evidências](#evidências).

| Requisito da entrega | Como foi atendido | Onde está | Print |
|---|---|---|---|
| VM no Azure por Azure CLI, com os comandos documentados | `az group create`, `az vm create`, `az vm open-port`, `az vm auto-shutdown` | [`scripts/provisionar-vm.sh`](scripts/provisionar-vm.sh), [passo 1](#1-provisionar-a-vm-com-azure-cli) | [01](docs/evidencias/01-azure-cli-vm-e-nsg.png), [02](docs/evidencias/02-provisionar-vm-script.png), [03](docs/evidencias/03-provisionar-vm-script-porta-e-desligamento.png) |
| Tags e desligamento automático da VM (aula 08) | tags `owner` e `purpose`; desligamento todo dia às 02:30 UTC (23:30 em Brasília) | [`scripts/provisionar-vm.sh`](scripts/provisionar-vm.sh) | [04](docs/evidencias/04-tags-e-auto-shutdown.png) |
| Docker e Docker Compose instalados na VM | repositório oficial do Docker no apt | [`scripts/instalar-docker.sh`](scripts/instalar-docker.sh), [passo 2](#2-instalar-o-docker-dentro-da-vm) | [05](docs/evidencias/05-ssh-docker-na-vm.png) |
| Aplicação Java em container | Spring Boot 4, imagem própria em dois estágios | [`Dockerfile`](Dockerfile) | [07](docs/evidencias/07-dockerfile-linhas-chave.png), [10](docs/evidencias/10-containers-em-background.png) |
| Nenhuma senha nas camadas da imagem | sem `ARG` com segredo; senhas só no `.env`, lidas pelo Compose | [`Dockerfile`](Dockerfile), [`.dockerignore`](.dockerignore) | [08](docs/evidencias/08-docker-history-sem-segredo.png) |
| Usuário não privilegiado | `USER guardario` (uid 1001) na API e `user: postgres` (uid 70) no banco | [`Dockerfile`](Dockerfile), [`docker-compose.yml`](docker-compose.yml) | [14](docs/evidencias/14-exec-api-usuario-diretorios.png), [15](docs/evidencias/15-exec-db-usuario-dados.png) |
| `WORKDIR` | `/workspace` no build e `/app` na execução | [`Dockerfile`](Dockerfile) | [07](docs/evidencias/07-dockerfile-linhas-chave.png), [14](docs/evidencias/14-exec-api-usuario-diretorios.png) |
| Variável de ambiente | `ENV` no Dockerfile e `environment` no Compose, com os valores no `.env` | [Variáveis de ambiente](#variáveis-de-ambiente) | [16](docs/evidencias/16-variaveis-e-porta.png) |
| Porta exposta | `EXPOSE 8080` e `ports: "8080:8080"` | [`Dockerfile`](Dockerfile), [`docker-compose.yml`](docker-compose.yml) | [10](docs/evidencias/10-containers-em-background.png), [16](docs/evidencias/16-variaveis-e-porta.png) |
| Banco em container, com porta e variáveis | PostgreSQL 16, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, porta 5432 | [`docker-compose.yml`](docker-compose.yml) | [09](docs/evidencias/09-compose-linhas-chave.png), [16](docs/evidencias/16-variaveis-e-porta.png) |
| Volume nomeado | `guardario-pgdata` em `/var/lib/postgresql/data` | [`docker-compose.yml`](docker-compose.yml) | [17](docs/evidencias/17-volume-nomeado.png) |
| Persistência dos dados | `docker compose down` e `up -d` com os mesmos dados | [passo 6](#6-persistência-dos-dados) | [49](docs/evidencias/49-persistencia-1-antes.png) a [52](docs/evidencias/52-persistencia-4-depois.png) |
| Duas tabelas relacionadas | `area_risco` 1:N `abrigo`, com a chave estrangeira `abrigo.area_id` | [passo 5](#5-select-direto-no-banco) | [19](docs/evidencias/19-select-tabelas-e-area-risco.png), [20](docs/evidencias/20-select-join-e-chave-estrangeira.png) |
| CRUD completo | POST, GET, PUT e DELETE de área e de abrigo, cada um seguido do SELECT | [passo 4](#4-crud-pelo-ip-público-com-select-depois-de-cada-operação) | [22](docs/evidencias/22-crud-create-area-requisicao.png) a [47](docs/evidencias/47-crud-get-area-404.png) |
| Compose com aplicação, banco, rede, volume, portas, variáveis e dependência | `depends_on` com `condition: service_healthy` | [`docker-compose.yml`](docker-compose.yml) | [09](docs/evidencias/09-compose-linhas-chave.png), [18](docs/evidencias/18-rede-guardario-net.png) |
| Containers em background | `docker compose up -d` | [passo 3](#3-subir-os-containers-com-docker-compose) | [10](docs/evidencias/10-containers-em-background.png) |
| Processos de cada serviço | `docker compose top`: a API roda como uid 1001 e o banco como uid 70 | [Evidências](#containers-executando-em-background) | [11](docs/evidencias/11-compose-top.png) |
| Logs | `docker compose logs` da API e do banco | [Evidências](#logs) | [12](docs/evidencias/12-logs-api.png), [13](docs/evidencias/13-logs-db.png) |
| Acesso aos containers, usuário e estrutura de diretórios | `docker exec` nos dois containers | [Evidências](#acesso-aos-containers-usuário-utilizado-e-estrutura-de-diretórios) | [14](docs/evidencias/14-exec-api-usuario-diretorios.png), [15](docs/evidencias/15-exec-db-usuario-dados.png) |
| SELECT diretamente no banco | `psql` dentro do container `guardario-db` | [passo 5](#5-select-direto-no-banco) | [19](docs/evidencias/19-select-tabelas-e-area-risco.png), [20](docs/evidencias/20-select-join-e-chave-estrangeira.png) |
| Arquitetura macro | diagrama com os nomes reais dos recursos | [Arquitetura macro](#arquitetura-macro) | [`docs/arquitetura.png`](docs/arquitetura.png) |

## How To: do zero até o CRUD na nuvem

Você precisa de uma conta Azure (a Azure for Students serve) e da Azure CLI. Quem não quiser instalar nada pode usar o [Azure Cloud Shell](https://shell.azure.com) em modo Bash, que já vem com a CLI, o `git` e o `ssh`.

### 1. Provisionar a VM com Azure CLI

No seu computador ou no Cloud Shell, no fluxo de script da aula 08: dar permissão de execução, executar e guardar a saída num `.log`.

```bash
git clone https://github.com/Raphael-Sinelli/guardario-devops.git
cd guardario-devops
chmod +x scripts/*.sh
./scripts/provisionar-vm.sh > provisionar-vm.log
cat provisionar-vm.log
```

Isso é Infraestrutura como Código: a VM, a rede, o firewall, as tags e o desligamento automático estão num arquivo versionado no Git, e rodar o mesmo script de novo recria o mesmo ambiente. O `.log` fica fora do Git (`*.log` está no `.gitignore`). Rode `az login` antes de executar o script, para o login não ficar misturado com a saída que vai para o arquivo.

O script roda os comandos abaixo, nesta ordem. Dá para colar um por um, se preferir:

```bash
az login

# 1. grupo de recursos, com as tags owner e purpose da aula 08
az group create --name rg-guardario --location northcentralus \
  --tags projeto=guardario disciplina=devops owner=GuardaRio purpose=GlobalSolution

# 2. VM Ubuntu 24.04 com rede, sub-rede, NSG (porta 22 liberada) e IP público fixo
az vm create \
  --resource-group rg-guardario \
  --name vm-guardario \
  --image Ubuntu2404 \
  --size Standard_B2als_v2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --vnet-name vnet-guardario --vnet-address-prefix 10.0.0.0/16 \
  --subnet snet-guardario --subnet-address-prefix 10.0.0.0/24 \
  --nsg nsg-guardario --nsg-rule SSH \
  --public-ip-address pip-guardario --public-ip-sku Standard \
  --tags projeto=guardario disciplina=devops owner=GuardaRio purpose=GlobalSolution

# 3. porta da API no NSG
az vm open-port --resource-group rg-guardario --name vm-guardario --port 8080 --priority 1010

# 4. desligamento automático todo dia às 02:30 UTC, que é 23:30 em Brasília
az vm auto-shutdown --resource-group rg-guardario --name vm-guardario --time 0230

# 5. IP público da VM
az vm show --show-details --resource-group rg-guardario --name vm-guardario \
  --query publicIps --output tsv
```

No fim, o script mostra o IP público. Guarde esse valor: ele é o `IP-PUBLICO` dos próximos passos.

A sua assinatura não tem cota na região ou não oferece o tamanho? Troque sem editar o arquivo:

```bash
LOCATION=brazilsouth VM_SIZE=Standard_B2s ./scripts/provisionar-vm.sh
```

### 2. Instalar o Docker dentro da VM

```bash
ssh azureuser@IP-PUBLICO

# a partir daqui, dentro da VM
git clone https://github.com/Raphael-Sinelli/guardario-devops.git
cd guardario-devops
./scripts/instalar-docker.sh
newgrp docker
```

O `instalar-docker.sh` segue o [guia oficial do Docker para Ubuntu](https://docs.docker.com/engine/install/ubuntu/): adiciona o repositório do Docker ao apt, instala `docker-ce`, `docker-buildx-plugin` e `docker-compose-plugin`, liga o serviço e põe o `azureuser` no grupo `docker`. O `newgrp docker` faz o grupo valer na sessão atual, sem precisar sair e entrar de novo.

```bash
docker --version
docker compose version
```

### 3. Subir os containers com Docker Compose

Ainda na VM, na pasta `guardario-devops`:

```bash
./scripts/gerar-env.sh           # cria o .env com senhas aleatórias e mostra o login do ADMIN
docker compose up -d --build     # constrói a imagem da API e sobe os dois containers em background
docker compose ps
```

O `gerar-env.sh` mostra o e-mail e a senha do ADMIN. Anote: é com esse usuário que se faz o CRUD. Quem preferir preencher à mão usa `cp .env.example .env` e edita os três campos vazios (`POSTGRES_PASSWORD`, `JWT_SECRET` e `ADMIN_PASSWORD`).

Na primeira subida o Docker baixa as imagens base e o Maven baixa as dependências dentro do build. Na nossa VM (`Standard_B2als_v2`) isso levou 71 segundos. Quando os dois containers aparecem como `healthy`, a API está pronta:

```bash
curl http://IP-PUBLICO:8080/actuator/health
# {"groups":["liveness","readiness"],"status":"UP"}
```

No navegador: `http://IP-PUBLICO:8080/swagger-ui/index.html`.

### 4. CRUD pelo IP público, com SELECT depois de cada operação

As duas tabelas do CRUD são `area_risco` e `abrigo`: uma área de risco tem vários abrigos, e todo abrigo pertence a uma área (`abrigo.area_id`). As consultas são públicas; as escritas pedem o token do ADMIN.

Deixe duas janelas abertas: o Swagger em `http://IP-PUBLICO:8080/swagger-ui/index.html` e um terminal na VM, na pasta `guardario-devops`. Depois de cada operação no Swagger, rode o SELECT no terminal para ver o que mudou no banco. Os dois SELECT usados:

```bash
# SELECT da tabela area_risco
docker exec -it guardario-db psql -U guardario -d guardario -c "SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco ORDER BY id;"

# SELECT da tabela abrigo, com o JOIN pela chave estrangeira
docker exec -it guardario-db psql -U guardario -d guardario -c "SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area FROM abrigo a JOIN area_risco r ON r.id = a.area_id ORDER BY a.id;"
```

Antes de começar, no Swagger: `POST /api/auth/login` com o e-mail e a senha do ADMIN, os do `.env` da VM. Copie o `token` da resposta, clique em **Authorize**, cole e confirme. Os usuários de teste que aparecem na descrição do Swagger são da carga do perfil `dev` e não existem na nuvem.

| # | Operação no Swagger | Resposta | SELECT no terminal | Prints |
|---|---|---|---|---|
| 1 | Create área: `POST /api/areas` com `{"nome":"Jardim Pantanal","cidade":"São Paulo","uf":"SP","populacaoEstimada":48000}` | 201, com o `id` da área | SELECT de `area_risco`: a área nova aparece | [22](docs/evidencias/22-crud-create-area-requisicao.png), [23](docs/evidencias/23-crud-create-area-resposta.png), [24](docs/evidencias/24-crud-create-area-select.png) |
| 2 | Create abrigo: `POST /api/abrigos` com `{"nome":"EMEF Jardim Pantanal","endereco":"Rua Capachós, 120","capacidade":120,"aceitaPets":true,"acessivelPcd":true,"areaId":ID-DA-AREA}` | 201, com o `id` do abrigo | SELECT com JOIN: o abrigo aparece ligado à área | [25](docs/evidencias/25-crud-create-abrigo-requisicao.png), [26](docs/evidencias/26-crud-create-abrigo-resposta.png), [27](docs/evidencias/27-crud-create-abrigo-select.png) |
| 3 | Read área: `GET /api/areas/{id}` | 200 | SELECT de `area_risco` com `WHERE id = ID-DA-AREA`: os mesmos dados | [28](docs/evidencias/28-crud-read-area-resposta.png), [29](docs/evidencias/29-crud-read-area-select.png) |
| 4 | Read abrigo: `GET /api/abrigos/{id}` | 200 | SELECT com JOIN e `WHERE a.id = ID-DO-ABRIGO`: os mesmos dados | [30](docs/evidencias/30-crud-read-abrigo-resposta.png), [31](docs/evidencias/31-crud-read-abrigo-select.png) |
| 5 | Update área: `PUT /api/areas/{id}` com `"populacaoEstimada":52000` | 200 | SELECT de `area_risco`: população 52000 | [32](docs/evidencias/32-crud-update-area-requisicao.png), [33](docs/evidencias/33-crud-update-area-resposta.png), [34](docs/evidencias/34-crud-update-area-select.png) |
| 6 | Update abrigo: `PUT /api/abrigos/{id}` com nome `EMEF Jardim Pantanal (ginásio)` e `"capacidade":150` | 200 | SELECT com JOIN: nome e capacidade novos | [35](docs/evidencias/35-crud-update-abrigo-requisicao.png), [36](docs/evidencias/36-crud-update-abrigo-resposta.png), [37](docs/evidencias/37-crud-update-abrigo-select.png) |
| 7 | Delete da área que ainda tem abrigo: `DELETE /api/areas/{id}` | 409 | os dois SELECT: nada saiu do banco | [38](docs/evidencias/38-crud-delete-area-com-abrigo-requisicao.png), [39](docs/evidencias/39-crud-delete-area-com-abrigo-409.png), [40](docs/evidencias/40-crud-delete-area-com-abrigo-select.png) |
| 8 | Delete abrigo: `DELETE /api/abrigos/{id}` | 204 | SELECT com JOIN: o abrigo sumiu | [41](docs/evidencias/41-crud-delete-abrigo-requisicao.png), [42](docs/evidencias/42-crud-delete-abrigo-204.png), [43](docs/evidencias/43-crud-delete-abrigo-select.png) |
| 9 | Delete área: `DELETE /api/areas/{id}` | 204 | SELECT de `area_risco`: a área sumiu | [44](docs/evidencias/44-crud-delete-area-requisicao.png), [45](docs/evidencias/45-crud-delete-area-204.png), [46](docs/evidencias/46-crud-delete-area-select.png) |
| 10 | Read da área apagada: `GET /api/areas/{id}` | 404 | não precisa | [47](docs/evidencias/47-crud-get-area-404.png) |

O 409 do passo 7 vem da regra da API que protege a chave estrangeira: uma área com abrigo ligado não pode ser apagada. Por isso o abrigo sai primeiro.

**Jeito rápido, com o script.** Faz o mesmo fluxo pelo IP público e, rodando na VM, mostra o SELECT depois de cada operação:

```bash
./scripts/testar-crud.sh http://IP-PUBLICO:8080
```

**Por curl**, de qualquer máquina:

```bash
API=http://IP-PUBLICO:8080

# login: guarda o token do ADMIN
TOKEN=$(curl -s -X POST $API/api/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"admin@guardario.com","senha":"SENHA-DO-ADMIN"}' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

# CREATE: área e abrigo ligado a ela
curl -i -X POST $API/api/areas -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"nome":"Jardim Pantanal","cidade":"São Paulo","uf":"SP","populacaoEstimada":48000}'

curl -i -X POST $API/api/abrigos -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"nome":"EMEF Jardim Pantanal","endereco":"Rua Capachós, 120","capacidade":120,"aceitaPets":true,"acessivelPcd":true,"areaId":1}'

# READ (público, sem token)
curl $API/api/areas/1
curl $API/api/abrigos/1

# UPDATE
curl -i -X PUT $API/api/areas/1 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"nome":"Jardim Pantanal","cidade":"São Paulo","uf":"SP","populacaoEstimada":52000}'

curl -i -X PUT $API/api/abrigos/1 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"nome":"EMEF Jardim Pantanal (ginásio)","endereco":"Rua Capachós, 120","capacidade":150,"aceitaPets":true,"acessivelPcd":true,"areaId":1}'

# DELETE: primeiro o abrigo (filho), depois a área (pai)
curl -i -X DELETE $API/api/abrigos/1 -H "Authorization: Bearer $TOKEN"
curl -i -X DELETE $API/api/areas/1   -H "Authorization: Bearer $TOKEN"
```

Troque o `1` pelos ids que o seu banco devolver.

### 5. SELECT direto no banco

Na VM, entrando no container do banco com `docker exec`:

```bash
docker exec -it guardario-db psql -U guardario -d guardario -c '\dt'

docker exec -it guardario-db psql -U guardario -d guardario \
  -c "SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco ORDER BY id;"

docker exec -it guardario-db psql -U guardario -d guardario \
  -c "SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area
        FROM abrigo a JOIN area_risco r ON r.id = a.area_id ORDER BY a.id;"

docker exec guardario-db psql -U guardario -d guardario -P pager=off -c "\d abrigo" | tail -3
```

O segundo SELECT junta as duas tabelas pela chave estrangeira: cada abrigo aparece com o nome da área a que pertence. O último comando mostra a própria chave estrangeira. O `-P pager=off` evita que o `psql` abra um paginador e trave o terminal.

### 6. Persistência dos dados

```bash
./scripts/testar-crud.sh http://IP-PUBLICO:8080 --manter   # cria e altera, mas não apaga
./scripts/evidencias.sh --persistencia
```

O segundo comando mostra o SELECT, roda `docker compose down` (que apaga os containers e a rede), lista o volume que ficou, sobe tudo de novo com `docker compose up -d` e repete o SELECT. Os containers são novos e os dados são os mesmos, porque estão no volume `guardario-pgdata`, fora dos containers.

À mão:

```bash
docker compose down
docker volume ls                 # guardario-pgdata continua lá
docker compose up -d
docker exec -it guardario-db psql -U guardario -d guardario -c "SELECT * FROM abrigo;"
```

Só o `docker compose down -v` apaga o volume, e com ele os dados.

## Evidências

Todos os prints abaixo são capturas de janelas reais: o Windows Terminal conectado por SSH na VM `vm-guardario` (o prompt `azureuser@vm-guardario` aparece em cada um) e o Chrome com `130.131.61.173:8080` na barra de endereço. Foram feitos em 17/11/2026 (UTC). Os grupos seguem a lista de evidências da página 38 do enunciado e os requisitos da página 37.

### Arquitetura macro da solução

O diagrama está na seção [Arquitetura macro](#arquitetura-macro), com os nomes reais de todos os recursos.

### VM Azure provisionada por Azure CLI

A VM `vm-guardario` está em `northcentralus`, tamanho `Standard_B2als_v2`, ligada, com o IP `130.131.61.173`. O NSG só libera as portas 22 e 8080.

![az vm list e az network nsg rule list](docs/evidencias/01-azure-cli-vm-e-nsg.png)

O script de provisionamento, aberto na VM, com as tags (linha 30), o `az group create` (linha 39) e o `az vm create` (linha 48).

![scripts/provisionar-vm.sh](docs/evidencias/02-provisionar-vm-script.png)

A continuação do mesmo script: o `az vm open-port` da 8080 (linha 67) e o `az vm auto-shutdown` (linha 76), que desliga a VM todo dia às 02:30 UTC, 23:30 em Brasília.

![scripts/provisionar-vm.sh, porta e desligamento](docs/evidencias/03-provisionar-vm-script-porta-e-desligamento.png)

As tags no formato da aula 08 (`owner` e `purpose`) e o desligamento automático aplicados na VM, e o agendamento confirmado: `Enabled`, `0230`, `UTC`.

![tags e desligamento automático](docs/evidencias/04-tags-e-auto-shutdown.png)

### Docker e Docker Compose instalados na VM

Acesso por SSH pelo IP público e as versões instaladas: Docker 29.10.0 e Docker Compose v5.7.1.

![ssh e versões do Docker](docs/evidencias/05-ssh-docker-na-vm.png)

### Dockerfile e container da aplicação

As linhas-chave do Dockerfile, lidas na VM: os dois `FROM` (build com JDK e execução com JRE Alpine), `WORKDIR /app`, `adduser` e `USER guardario`, `ENV`, `EXPOSE 8080`, `HEALTHCHECK` e `ENTRYPOINT`.

![linhas-chave do Dockerfile](docs/evidencias/07-dockerfile-linhas-chave.png)

O `docker history` da imagem: 21 camadas, nenhuma com senha, segredo ou token, e nenhum `ARG` (a aula 10 avisa que segredo em `ARG` aparece aqui). As senhas chegam só em tempo de execução, pelo `.env`.

![docker history sem segredo](docs/evidencias/08-docker-history-sem-segredo.png)

### Docker Compose

As linhas-chave do `docker-compose.yml`: serviços `db` e `api`, imagens, usuário `postgres`, portas, volume `pgdata` (nome `guardario-pgdata`), rede `guardario-net`, `restart: unless-stopped` e a dependência com `condition: service_healthy`.

![linhas-chave do docker-compose.yml](docs/evidencias/09-compose-linhas-chave.png)

### Containers executando em background

Os dois containers `Up (healthy)`, com a coluna PORTS: a API publicada em `0.0.0.0:8080` e o banco só em `127.0.0.1:5432`.

![docker compose ps](docs/evidencias/10-containers-em-background.png)

O `docker compose top`, que lista os processos de cada serviço do arquivo: o serviço `api` roda como uid 1001 (`guardario`) e o serviço `db` como uid 70 (`postgres`), com as conexões da API abertas no banco.

![docker compose top](docs/evidencias/11-compose-top.png)

### Logs

Logs da API: conexão em `jdbc:postgresql://db:5432/guardario`, PostgreSQL 16.16, Tomcat na porta 8080 e `Started GuardaRioApplication`. Aparecem duas subidas porque a VM foi desligada e religada entre elas.

![logs da API](docs/evidencias/12-logs-api.png)

Logs do banco: `database system is ready to accept connections`.

![logs do banco](docs/evidencias/13-logs-db.png)

### Acesso aos containers, usuário utilizado e estrutura de diretórios

Container da API: o usuário é `guardario` (uid 1001), não root. O diretório de trabalho é `/app`, só com o `app.jar`, que pertence ao root. O processo 1 é o `java -jar app.jar`, rodando como `guardario`.

![docker exec na API](docs/evidencias/14-exec-api-usuario-diretorios.png)

Container do banco: o usuário é `postgres` (uid 70), e o diretório dos dados é `/var/lib/postgresql/data`, onde o volume está montado.

![docker exec no banco](docs/evidencias/15-exec-db-usuario-dados.png)

### Variáveis de ambiente e portas

As variáveis dos dois containers, filtradas para não mostrar senha nem chave, e as portas publicadas.

![variáveis e portas](docs/evidencias/16-variaveis-e-porta.png)

### Volume nomeado e rede

O volume `guardario-pgdata`, criado pelo Compose, com o ponto de montagem em `/var/lib/docker/volumes/guardario-pgdata/_data`.

![volume nomeado](docs/evidencias/17-volume-nomeado.png)

A rede `guardario-net`, do tipo bridge, com os dois containers. De dentro da API, o nome `db` resolve para o IP do banco e a porta 5432 responde.

![rede guardario-net](docs/evidencias/18-rede-guardario-net.png)

### SELECT diretamente no banco

As 8 tabelas e o SELECT de `area_risco`.

![\dt e SELECT de area_risco](docs/evidencias/19-select-tabelas-e-area-risco.png)

O SELECT com JOIN entre `abrigo` e `area_risco` e a chave estrangeira `area_id` referenciando `area_risco(id)`.

![JOIN e chave estrangeira](docs/evidencias/20-select-join-e-chave-estrangeira.png)

### CRUD funcionando pelo IP público, com SELECT depois de cada operação

O Swagger aberto pelo IP público, já autorizado como ADMIN (cadeados fechados). O login foi feito antes do print, para o token não aparecer.

![Swagger pelo IP público](docs/evidencias/21-swagger-ip-publico.png)

Em cada operação: um print da requisição antes do Execute, um da resposta (Request URL e código HTTP) e um do SELECT no banco. O print da resposta começa no Request URL: o bloco Curl, que fica acima dele, mostraria o token.

**1. Create área (201) e SELECT.** A área 6 aparece no banco com população 48000.

![Create área, requisição](docs/evidencias/22-crud-create-area-requisicao.png)
![Create área, resposta 201](docs/evidencias/23-crud-create-area-resposta.png)
![Create área, SELECT](docs/evidencias/24-crud-create-area-select.png)

**2. Create abrigo (201) e SELECT com JOIN.** O abrigo 6 aparece ligado à área 6.

![Create abrigo, requisição](docs/evidencias/25-crud-create-abrigo-requisicao.png)
![Create abrigo, resposta 201](docs/evidencias/26-crud-create-abrigo-resposta.png)
![Create abrigo, SELECT](docs/evidencias/27-crud-create-abrigo-select.png)

**3. Read área (200) e SELECT.** A API e o banco mostram os mesmos dados da área 6.

![Read área, resposta 200](docs/evidencias/28-crud-read-area-resposta.png)
![Read área, SELECT](docs/evidencias/29-crud-read-area-select.png)

**4. Read abrigo (200) e SELECT.** A API e o banco mostram os mesmos dados do abrigo 6.

![Read abrigo, resposta 200](docs/evidencias/30-crud-read-abrigo-resposta.png)
![Read abrigo, SELECT](docs/evidencias/31-crud-read-abrigo-select.png)

**5. Update área (200) e SELECT.** A população da área 6 passa de 48000 para 52000.

![Update área, requisição](docs/evidencias/32-crud-update-area-requisicao.png)
![Update área, resposta 200](docs/evidencias/33-crud-update-area-resposta.png)
![Update área, SELECT](docs/evidencias/34-crud-update-area-select.png)

**6. Update abrigo (200) e SELECT.** O abrigo 6 passa a se chamar EMEF Jardim Pantanal (ginásio), com capacidade 150.

![Update abrigo, requisição](docs/evidencias/35-crud-update-abrigo-requisicao.png)
![Update abrigo, resposta 200](docs/evidencias/36-crud-update-abrigo-resposta.png)
![Update abrigo, SELECT](docs/evidencias/37-crud-update-abrigo-select.png)

**7. Delete da área com abrigo ligado (409) e SELECT.** A API recusa, e o SELECT mostra que nada saiu das duas tabelas.

![Delete área com abrigo, requisição](docs/evidencias/38-crud-delete-area-com-abrigo-requisicao.png)
![Delete área com abrigo, resposta 409](docs/evidencias/39-crud-delete-area-com-abrigo-409.png)
![Delete área com abrigo, SELECT](docs/evidencias/40-crud-delete-area-com-abrigo-select.png)

**8. Delete abrigo (204) e SELECT.** O abrigo 6 sai do banco.

![Delete abrigo, requisição](docs/evidencias/41-crud-delete-abrigo-requisicao.png)
![Delete abrigo, resposta 204](docs/evidencias/42-crud-delete-abrigo-204.png)
![Delete abrigo, SELECT](docs/evidencias/43-crud-delete-abrigo-select.png)

**9. Delete área (204) e SELECT.** A área 6 sai do banco.

![Delete área, requisição](docs/evidencias/44-crud-delete-area-requisicao.png)
![Delete área, resposta 204](docs/evidencias/45-crud-delete-area-204.png)
![Delete área, SELECT](docs/evidencias/46-crud-delete-area-select.png)

**10. Read da área apagada (404).**

![GET da área apagada, 404](docs/evidencias/47-crud-get-area-404.png)

Os registros de id 2 que aparecem nos SELECT são de um teste anterior e ficaram no banco de propósito.

### Persistência dos dados

Um CRUD com `--manter` deixa a área 9 e o abrigo 9 no banco.

![registros de teste](docs/evidencias/48-persistencia-0-registros-de-teste.png)

Os dados antes de derrubar os containers.

![antes do down](docs/evidencias/49-persistencia-1-antes.png)

`docker compose down`: os dois containers e a rede são removidos, o `docker ps -a` fica vazio e o volume `guardario-pgdata` continua no `docker volume ls`.

![docker compose down](docs/evidencias/50-persistencia-2-down.png)

`docker compose up -d`: rede e containers novos, os dois `healthy`, com o mesmo volume.

![docker compose up -d](docs/evidencias/51-persistencia-3-up.png)

Os mesmos dados, lidos pelos containers novos.

![depois do up](docs/evidencias/52-persistencia-4-depois.png)

### CRUD pelo script testar-crud.sh

O resumo: uma linha por chamada HTTP, com o status recebido e o esperado.

![testar-crud.sh, resumo](docs/evidencias/53-testar-crud-resumo.png)

A saída completa de outra execução, gravada num arquivo na VM e mostrada em quatro telas, com o corpo enviado, a resposta e o SELECT depois de cada operação.

![testar-crud.sh, saída completa 1](docs/evidencias/54-testar-crud-completo-1.png)
![testar-crud.sh, saída completa 2](docs/evidencias/55-testar-crud-completo-2.png)
![testar-crud.sh, saída completa 3](docs/evidencias/56-testar-crud-completo-3.png)
![testar-crud.sh, saída completa 4](docs/evidencias/57-testar-crud-completo-4.png)

### Scripts do repositório

Os sete scripts na VM, com a primeira linha de cada um, que diz o que ele faz. O `demo-video.sh` é o roteiro de demonstração usado no vídeo: na VM, `./scripts/demo-video.sh` digita cada comando na tela, executa esse mesmo comando ao vivo e mostra cena por cena os containers, os logs, o acesso, as variáveis, o volume, a rede, o SELECT, o CRUD pelo IP público com SELECT depois de cada operação e a persistência, e apaga sozinho os registros de teste no fim. `./scripts/demo-video.sh --cena 14` começa direto numa cena; `--rapido` e `--lento` mudam a velocidade da digitação. Com `--corrido`, roda todas as cenas em sequência, sem Enter e sem limpar a tela: cada etapa abre com uma faixa com o título, a data, a hora e o nome da máquina, ocupa uma tela, e no fim vem a faixa PROVA AO VIVO com o `docker compose ps`, o health e um GET pelo IP público.

![scripts do repositório](docs/evidencias/06-scripts-do-repositorio.png)

### Ciclo da VM: desligar e religar

`az vm deallocate`: a VM fica `VM deallocated` e a API para de responder (health 000).

![deallocate](docs/evidencias/58-ciclo-vm-1-deallocate.png)

`az vm start`: a VM volta com o mesmo IP `130.131.61.173` e a API responde `UP`, sem ninguém entrar na VM.

![start com o mesmo IP](docs/evidencias/59-ciclo-vm-2-start-mesmo-ip.png)

Dentro da VM: os dois containers voltaram `healthy` sozinhos e o abrigo 9 continua no banco.

![containers e dados depois do start](docs/evidencias/60-ciclo-vm-3-containers-e-dados.png)

### Saídas completas em texto

Complemento dos prints, com a saída inteira de cada script, capturada em 16/11/2026:

| Arquivo | O que tem |
|---|---|
| [`01-provisionamento-azure-cli.txt`](docs/evidencias/texto/01-provisionamento-azure-cli.txt) | saída do `scripts/provisionar-vm.sh` |
| [`02-crud-ip-publico.txt`](docs/evidencias/texto/02-crud-ip-publico.txt) | `testar-crud.sh` rodado na VM, com o SELECT depois de cada operação |
| [`03-crud-de-fora-da-vm.txt`](docs/evidencias/texto/03-crud-de-fora-da-vm.txt) | o mesmo script rodado de um computador fora da Azure |
| [`04-evidencias-containers.txt`](docs/evidencias/texto/04-evidencias-containers.txt) | `evidencias.sh`: containers, logs, exec, variáveis, SELECT, volume e rede |
| [`05-persistencia.txt`](docs/evidencias/texto/05-persistencia.txt) | `evidencias.sh --persistencia` |
| [`09-ciclo-deallocate-start.txt`](docs/evidencias/texto/09-ciclo-deallocate-start.txt) | ciclo `az vm deallocate` e `az vm start` |

Para gerar tudo de novo na VM: `./scripts/evidencias.sh` e `./scripts/evidencias.sh --persistencia`.

## Dockerfile explicado

O [`Dockerfile`](Dockerfile) tem dois estágios.

**Estágio `build`** (`eclipse-temurin:21-jdk`). Copia primeiro o `pom.xml` e o Maven Wrapper e baixa as dependências; só depois copia o código e empacota. O Docker guarda cada instrução numa camada, então a camada das dependências é reaproveitada enquanto o `pom.xml` não muda, e o build depois de mexer só no código fica mais rápido.

**Estágio `runtime`** (`eclipse-temurin:21-jre-alpine`). Recebe apenas o `.jar` pronto. O JDK, o Maven, o repositório local do Maven e o código-fonte ficam no primeiro estágio. A imagem final tem 421 MB e não leva compilador nem código-fonte.

| Instrução | Por quê |
|---|---|
| `RUN addgroup` e `adduser` + `USER guardario` | a aplicação roda com um usuário de sistema, sem senha, sem shell e sem home. Quem explorar uma falha da API cai nesse usuário, não no root |
| `WORKDIR /app` | diretório fixo da aplicação; o `.jar` é do root e o usuário `guardario` só lê |
| `ENV` | padrões que não são segredo: perfil `prod`, porta, fuso UTC e limite de memória da JVM |
| `EXPOSE 8080` | documenta a porta em que a aplicação escuta. Quem publica na VM é o `ports` do Compose |
| `HEALTHCHECK` | o Docker chama `/actuator/health`; o container só fica `healthy` quando a API e a conexão com o banco respondem |
| `ENTRYPOINT ["java", "-jar", "app.jar"]` | forma exec: o `java` é o processo 1 e recebe o sinal de parada do `docker compose down` |

Nenhuma senha entra na imagem. O [`.dockerignore`](.dockerignore) deixa passar só o código da API, então nem o `.env` chega ao build.

## Docker Compose explicado

O [`docker-compose.yml`](docker-compose.yml) define tudo num arquivo só:

| Item | Configuração |
|---|---|
| Aplicação | serviço `api`, construído pelo `Dockerfile`, container `guardario-api` |
| Banco | serviço `db`, imagem `postgres:16-alpine`, container `guardario-db` |
| Rede | `guardario-net` (bridge). Nela o Docker resolve o nome `db` para o IP do container do banco, por isso a URL da API é `jdbc:postgresql://db:5432/guardario` |
| Volume | `guardario-pgdata`, montado em `/var/lib/postgresql/data` |
| Portas | `8080:8080` na API. No banco, `127.0.0.1:5432:5432`: publicada só para a própria VM |
| Variáveis | bloco `environment` de cada serviço, com os valores lidos do `.env` |
| Dependência | `depends_on` com `condition: service_healthy` |
| Reinício | `restart: unless-stopped`: os containers voltam sozinhos quando a VM é religada |

**Por que `condition: service_healthy`.** O `depends_on` simples só espera o container do banco ser criado, e o PostgreSQL leva alguns segundos para aceitar conexão. Com a condição, o Compose espera o `pg_isready` do healthcheck passar e só então inicia a API.

**Por que a porta do banco só no loopback.** A API não precisa dela, porque fala com o banco pela rede interna. A porta fica publicada em `127.0.0.1` para dar acesso por túnel SSH a quem administra (`ssh -L 5432:127.0.0.1:5432 azureuser@IP-PUBLICO` e depois DBeaver ou psql em `localhost:5432`), sem expor o banco na internet. O NSG também não libera a 5432.

**Por que o volume e a rede não têm o prefixo do projeto.** Sem a chave `name:`, o Compose põe o nome do projeto na frente dos recursos, como o `moneyhub_mysql-dimdim-data` e o `moneyhub_dimdim-network` da aula 11; aqui eles seriam `guardario_pgdata` e `guardario_guardario-net`. Com `name: guardario-pgdata` e `name: guardario-net` no arquivo, os nomes ficam fixos e os comandos de `inspect` do README funcionam em qualquer pasta.

**Por que `environment` e não `env_file`.** O Compose lê o `.env` da pasta sozinho para preencher os `${...}` do arquivo. Cada serviço recebe no `environment` só as variáveis de que precisa: o banco não recebe a `JWT_SECRET`, por exemplo. Com `env_file`, todas as linhas do `.env` iriam para o serviço.

## Variáveis de ambiente

Os valores ficam no `.env`, que não vai para o Git. O modelo é o [`.env.example`](.env.example).

| Variável | Container | Para que serve |
|---|---|---|
| `POSTGRES_DB`, `POSTGRES_USER` | banco e API | nome do banco e usuário (padrão `guardario`) |
| `POSTGRES_PASSWORD` | banco e API | senha do banco. Na API chega como `DB_PASSWORD` |
| `DB_URL` | API | montada no Compose: `jdbc:postgresql://db:5432/guardario` |
| `SPRING_PROFILES_ACTIVE` | API | `prod`: PostgreSQL, sem carga de demonstração |
| `JWT_SECRET` | API | chave que assina os tokens. Sem ela a API não sobe |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | API | primeiro ADMIN, criado na primeira subida |
| `SWAGGER_ENABLED` | API | liga o Swagger UI no perfil `prod` |
| `SEED_ENABLED` | API | carga de demonstração. Fica `false` na nuvem |
| `CORS_ALLOWED_ORIGINS` | API | origens liberadas para o app |
| `API_PORT`, `DB_PORT` | Compose | portas publicadas na VM |

O Compose recusa subir se faltar `POSTGRES_PASSWORD`, `JWT_SECRET`, `ADMIN_EMAIL` ou `ADMIN_PASSWORD`, e diz qual falta.

## Operação do dia a dia

```bash
# acompanhar os logs ao vivo
docker compose logs -f api

# atualizar a aplicação depois de um push
git pull && docker compose up -d --build

# parar e remover os containers (os dados ficam no volume)
docker compose down
```

### Desligar e religar a VM

A VM fica desligada fora das demonstrações, para não gastar crédito. Além disso, o desligamento automático (`az vm auto-shutdown`, no passo 1) desliga a VM todo dia às 02:30 UTC, 23:30 em Brasília, se alguém esquecer ela ligada. Para ligar e desligar na mão, do computador ou do Cloud Shell:

```bash
# desligar: libera a máquina e para a cobrança de computação (o disco e o IP continuam reservados)
az vm deallocate --resource-group rg-guardario --name vm-guardario

# religar
az vm start --resource-group rg-guardario --name vm-guardario

# conferir o estado e o IP
az vm show --show-details --resource-group rg-guardario --name vm-guardario \
  --query "{estado:powerState, ip:publicIps}" --output table
```

Só o `az vm start` basta: não é preciso entrar na VM nem rodar `docker compose up`. O serviço do Docker sobe com a VM e os dois containers têm `restart: unless-stopped`. O IP público é do SKU Standard, com alocação fixa, e não muda.

Testamos o ciclo em 16/11/2026: o IP continuou `130.131.61.173`, a API respondeu no IP público 37 segundos depois de o `az vm start` terminar, os dois containers voltaram `healthy` sozinhos e os dados estavam no volume. Repetimos em 17/11/2026, com os prints em [Ciclo da VM: desligar e religar](#ciclo-da-vm-desligar-e-religar). A saída completa do primeiro teste está em [`docs/evidencias/texto/09-ciclo-deallocate-start.txt`](docs/evidencias/texto/09-ciclo-deallocate-start.txt).

Para apagar tudo depois da apresentação: `./scripts/remover-recursos.sh`.

## Segurança

* Nenhuma senha ou chave no repositório. O `.env` está no `.gitignore` e é gerado na VM com permissão 600.
* Os dois containers rodam sem root: `guardario` (uid 1001) na API e `postgres` (uid 70) no banco.
* O banco não é acessível pela internet: a porta 5432 fica só no loopback da VM e o NSG não a libera.
* O SSH da VM aceita só chave, sem senha.
* A carga de demonstração, que tem usuários com senha conhecida, fica desligada na nuvem.
* O Swagger fica ligado para a demonstração; para desligar, `SWAGGER_ENABLED=false` no `.env` e `docker compose up -d`.

## Problemas comuns

| Sintoma | Causa provável e saída |
|---|---|
| `az vm create` falha com `SkuNotAvailable` ou erro de política de região | a assinatura não oferece o tamanho ou a região. Rode com outra `LOCATION` permitida pela sua assinatura ou outro `VM_SIZE` |
| `az` responde `ExpiredAuthenticationToken` | o login da Azure CLI venceu: `az account clear` e depois `az login --use-device-code` |
| `permission denied` ao rodar `docker` na VM | o grupo `docker` ainda não vale na sessão: `newgrp docker` ou saia e entre de novo por ssh |
| `docker compose up` para com `Defina POSTGRES_PASSWORD no .env` | falta o `.env`: `./scripts/gerar-env.sh` |
| O navegador não abre `http://IP-PUBLICO:8080` | confira `docker compose ps` (os dois `healthy`) e a regra da 8080 no NSG: `az network nsg rule list -g rg-guardario --nsg-name nsg-guardario -o table` |
| A API reinicia sem parar | o motivo está em `docker compose logs api`. Confira primeiro o `.env`: a `JWT_SECRET` precisa de 32 caracteres ou mais e a `ADMIN_PASSWORD`, de 8 |
| Login do ADMIN dá 401 depois de trocar `ADMIN_PASSWORD` no `.env` | o ADMIN é criado só uma vez, na primeira subida. A senha que vale é a daquela subida |
| O `psql \d` trava no terminal | o `psql` abriu um paginador. Use `-P pager=off` |

## Uso de IA generativa

Este projeto usou o Claude (Anthropic) como apoio para organizar a infraestrutura, escrever e revisar os scripts, o Dockerfile, o Compose e este README. Todo o conteúdo foi revisado, executado na VM e é explicado pelos integrantes do grupo. As decisões de arquitetura e os testes foram validados pela equipe.
