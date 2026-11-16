# GuardaRio · DevOps Tools & Cloud Computing

**Global Solution 2026/2 · FIAP · CitizenTech**

O GuardaRio é um alerta comunitário de enchentes: estações medem o nível do rio, a API gera os alertas da área e o app mostra ao morador os abrigos com vaga. Este repositório coloca a **API Java (Spring Boot) e o PostgreSQL em containers Docker, numa VM do Microsoft Azure criada por Azure CLI**.

| | |
|---|---|
| Aplicação no ar | `http://IP-PUBLICO:8080/swagger-ui.html` (o IP sai no fim do passo 1) |
| Vídeo da demonstração | _link do YouTube (não listado)_ |
| Código da API | pasta [`api/`](api/), a mesma API da entrega de Java Advanced ([guardario-api](https://github.com/Raphael-Sinelli/guardario-api)) |

## Integrantes

| Nome | RM |
|---|---|
| Henrique Spoltore Moreno Pavão dos Santos | RM568130 |
| Raphael Oliveira Sinelli Mendonça | RM568346 |
| Arthur Lins Belarmino | RM566845 |

## Sumário

- [Arquitetura macro](#arquitetura-macro)
- [O que tem neste repositório](#o-que-tem-neste-repositório)
- [Onde está cada requisito](#onde-está-cada-requisito)
- [How To: do zero até o CRUD na nuvem](#how-to-do-zero-até-o-crud-na-nuvem)
  - [1. Provisionar a VM com Azure CLI](#1-provisionar-a-vm-com-azure-cli)
  - [2. Instalar o Docker dentro da VM](#2-instalar-o-docker-dentro-da-vm)
  - [3. Subir os containers com Docker Compose](#3-subir-os-containers-com-docker-compose)
  - [4. CRUD pelo IP público](#4-crud-pelo-ip-público)
  - [5. SELECT direto no banco](#5-select-direto-no-banco)
  - [6. Persistência dos dados](#6-persistência-dos-dados)
- [Evidências](#evidências)
- [Dockerfile explicado](#dockerfile-explicado)
- [Docker Compose explicado](#docker-compose-explicado)
- [Variáveis de ambiente](#variáveis-de-ambiente)
- [Operação do dia a dia](#operação-do-dia-a-dia)
- [Segurança](#segurança)
- [Problemas comuns](#problemas-comuns)
- [Uso de IA generativa](#uso-de-ia-generativa)

## Arquitetura macro

![Arquitetura macro do GuardaRio na Azure](docs/arquitetura.png)

O morador (app), o agente da Defesa Civil (Swagger) e a ponte das estações IoT chegam pela internet ao IP público da VM, na porta 8080. O NSG da Azure só deixa entrar a 22 (SSH) e a 8080 (API). Dentro da VM, o Docker Compose mantém dois containers na rede `guardario-net`: a API fala com o banco pelo nome `db`, e o banco grava no volume nomeado `guardario-pgdata`.

| Recurso | Nome | Detalhe |
|---|---|---|
| Grupo de recursos | `rg-guardario` | região `brazilsouth` |
| Rede virtual e sub-rede | `vnet-guardario` / `snet-guardario` | `10.0.0.0/16` e `10.0.0.0/24` |
| Firewall (NSG) | `nsg-guardario` | entrada: TCP 22 e TCP 8080 |
| IP público | `pip-guardario` | SKU Standard, fixo |
| Máquina virtual | `vm-guardario` | Ubuntu Server 24.04 LTS, `Standard_B2s` (2 vCPU, 4 GB) |
| Rede Docker | `guardario-net` | bridge |
| Container da aplicação | `guardario-api` | imagem `guardario-api:1.0.0`, porta `8080:8080`, usuário `guardario` |
| Container do banco | `guardario-db` | imagem `postgres:16-alpine`, porta `127.0.0.1:5432:5432`, usuário `postgres` |
| Volume nomeado | `guardario-pgdata` | montado em `/var/lib/postgresql/data` |

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
│   └── remover-recursos.sh  apaga o grupo de recursos depois da apresentação
└── docs/
    ├── arquitetura.png      arquitetura macro (e o .svg editável)
    └── evidencias/          prints e saídas reais da VM
```

## Onde está cada requisito

| Requisito da entrega | Como foi atendido | Onde conferir |
|---|---|---|
| VM no Azure por Azure CLI, com os comandos documentados | `az group create`, `az vm create`, `az vm open-port` | [`scripts/provisionar-vm.sh`](scripts/provisionar-vm.sh), [passo 1](#1-provisionar-a-vm-com-azure-cli) |
| Docker e Docker Compose instalados na VM | repositório oficial do Docker no apt | [`scripts/instalar-docker.sh`](scripts/instalar-docker.sh), [passo 2](#2-instalar-o-docker-dentro-da-vm) |
| Aplicação Java em container | Spring Boot 4, imagem própria em dois estágios | [`Dockerfile`](Dockerfile) |
| Usuário não privilegiado | `USER guardario` (uid 1001) na API e `user: postgres` (uid 70) no banco | [`Dockerfile`](Dockerfile), [`docker-compose.yml`](docker-compose.yml) |
| `WORKDIR` | `/workspace` no build e `/app` na execução | [`Dockerfile`](Dockerfile) |
| Variável de ambiente | `ENV` no Dockerfile e `environment` no Compose, com os valores no `.env` | [Variáveis de ambiente](#variáveis-de-ambiente) |
| Porta exposta | `EXPOSE 8080` e `ports: "8080:8080"` | [`Dockerfile`](Dockerfile), [`docker-compose.yml`](docker-compose.yml) |
| Banco em container, com porta e variáveis | PostgreSQL 16, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, porta 5432 | [`docker-compose.yml`](docker-compose.yml) |
| Volume nomeado e persistência | `guardario-pgdata` em `/var/lib/postgresql/data` | [passo 6](#6-persistência-dos-dados) |
| Duas tabelas relacionadas | `area_risco` 1:N `abrigo`, com a chave estrangeira `abrigo.area_id` | [passo 5](#5-select-direto-no-banco) |
| CRUD completo | POST, GET, PUT e DELETE de área e de abrigo | [passo 4](#4-crud-pelo-ip-público) |
| Compose com aplicação, banco, rede, volume, portas, variáveis e dependência | `depends_on` com `condition: service_healthy` | [`docker-compose.yml`](docker-compose.yml) |
| Containers em background | `docker compose up -d` | [passo 3](#3-subir-os-containers-com-docker-compose) |
| Logs, acesso aos containers, usuário e diretórios | `docker compose logs` e `docker exec` nos dois containers | [Evidências](#evidências) |
| Arquitetura macro | diagrama com os nomes reais dos recursos | [Arquitetura macro](#arquitetura-macro) |

## How To: do zero até o CRUD na nuvem

Você precisa de uma conta Azure (a Azure for Students serve) e da Azure CLI. Quem não quiser instalar nada pode usar o [Azure Cloud Shell](https://shell.azure.com) em modo Bash, que já vem com a CLI, o `git` e o `ssh`.

### 1. Provisionar a VM com Azure CLI

No seu computador ou no Cloud Shell:

```bash
git clone https://github.com/Raphael-Sinelli/guardario-devops.git
cd guardario-devops
./scripts/provisionar-vm.sh
```

O script roda os comandos abaixo, nesta ordem. Dá para colar um por um, se preferir:

```bash
az login

# 1. grupo de recursos
az group create --name rg-guardario --location brazilsouth \
  --tags projeto=guardario disciplina=devops

# 2. VM Ubuntu 24.04 com rede, sub-rede, NSG (porta 22 liberada) e IP público fixo
az vm create \
  --resource-group rg-guardario \
  --name vm-guardario \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --vnet-name vnet-guardario --vnet-address-prefix 10.0.0.0/16 \
  --subnet snet-guardario --subnet-address-prefix 10.0.0.0/24 \
  --nsg nsg-guardario --nsg-rule SSH \
  --public-ip-address pip-guardario --public-ip-sku Standard \
  --tags projeto=guardario disciplina=devops

# 3. porta da API no NSG
az vm open-port --resource-group rg-guardario --name vm-guardario --port 8080 --priority 1010

# 4. IP público da VM
az vm show --show-details --resource-group rg-guardario --name vm-guardario \
  --query publicIps --output tsv
```

No fim, o script mostra o IP público. Guarde esse valor: ele é o `IP-PUBLICO` dos próximos passos.

A assinatura não tem cota na região ou não oferece o tamanho? Troque sem editar o arquivo:

```bash
LOCATION=eastus VM_SIZE=Standard_B2s ./scripts/provisionar-vm.sh
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

O `gerar-env.sh` mostra o e-mail e a senha do ADMIN. Anote: é com esse usuário que se faz o CRUD. Quem preferir preencher à mão usa `cp .env.example .env` e edita os quatro campos vazios.

A primeira subida leva alguns minutos, porque o Maven baixa as dependências dentro do build. Quando os dois containers aparecem como `healthy`, a API está pronta:

```bash
curl http://IP-PUBLICO:8080/actuator/health
# {"groups":["liveness","readiness"],"status":"UP"}
```

No navegador: `http://IP-PUBLICO:8080/swagger-ui.html`.

### 4. CRUD pelo IP público

As duas tabelas do CRUD são `area_risco` e `abrigo`: uma área de risco tem vários abrigos, e todo abrigo pertence a uma área (`abrigo.area_id`). As consultas são públicas; as escritas pedem o token do ADMIN.

**Jeito rápido, com o script** (na VM ele mostra também o SELECT depois de cada operação):

```bash
./scripts/testar-crud.sh http://IP-PUBLICO:8080
```

Ele faz o login, cria uma área e um abrigo, lê, altera e apaga os dois, e confere o status HTTP de cada chamada. Antes de apagar, tenta excluir a área que ainda tem abrigo e recebe 409: é a chave estrangeira protegendo a relação.

**Pelo Swagger**, em `http://IP-PUBLICO:8080/swagger-ui.html`:

1. `POST /api/auth/login` com o e-mail e a senha do ADMIN. Copie o `token` da resposta.
2. Botão **Authorize**, cole o token e confirme.
3. `POST /api/areas` cria a área (201). Guarde o `id`.
4. `POST /api/abrigos` com esse `areaId` cria o abrigo (201).
5. `GET /api/areas/{id}` e `GET /api/abrigos/{id}` leem os dois (200).
6. `PUT /api/areas/{id}` e `PUT /api/abrigos/{id}` alteram (200).
7. `DELETE /api/abrigos/{id}` e depois `DELETE /api/areas/{id}` apagam (204).

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

### 5. SELECT direto no banco

Na VM, entrando no container do banco com `docker exec`:

```bash
docker exec -it guardario-db psql -U guardario -d guardario -c '\dt'

docker exec -it guardario-db psql -U guardario -d guardario \
  -c "SELECT id, nome, cidade, uf, populacao_estimada FROM area_risco ORDER BY id;"

docker exec -it guardario-db psql -U guardario -d guardario \
  -c "SELECT a.id, a.nome, a.capacidade, a.ocupacao, a.status, a.area_id, r.nome AS area
        FROM abrigo a JOIN area_risco r ON r.id = a.area_id ORDER BY a.id;"
```

O segundo SELECT junta as duas tabelas pela chave estrangeira: cada abrigo aparece com o nome da área a que pertence.

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

Um comando reúne todas, na VM:

```bash
./scripts/evidencias.sh
```

| O que mostra | Comando |
|---|---|
| Containers em execução, em background | `docker compose ps` |
| Logs da aplicação e do banco | `docker compose logs --tail=25 api` e `docker compose logs --tail=15 db` |
| Acesso ao container da aplicação, usuário e diretórios | `docker exec guardario-api sh -c 'whoami; id; pwd; ls -la'` |
| Acesso ao container do banco, usuário e diretório dos dados | `docker exec guardario-db sh -c 'whoami; id; ls -ld /var/lib/postgresql/data'` |
| Variáveis de ambiente dos dois containers | `docker exec guardario-api env` e `docker exec guardario-db env` |
| SELECT nas duas tabelas e a chave estrangeira | `docker exec guardario-db psql -U guardario -d guardario -c "..."` |
| Volume nomeado | `docker volume ls` e `docker volume inspect guardario-pgdata` |
| Rede e comunicação entre os containers | `docker network inspect guardario-net` e `docker exec guardario-api nslookup db` |
| Persistência | `./scripts/evidencias.sh --persistencia` |

As saídas reais da VM e os prints estão em [`docs/evidencias/`](docs/evidencias/).

## Dockerfile explicado

O [`Dockerfile`](Dockerfile) tem dois estágios.

**Estágio `build`** (`eclipse-temurin:21-jdk`). Copia primeiro o `pom.xml` e o Maven Wrapper e baixa as dependências; só depois copia o código e empacota. Como o Docker guarda cada instrução numa camada, a camada das dependências é reaproveitada enquanto o `pom.xml` não muda, e um build depois de mexer só no código fica bem mais rápido.

**Estágio `runtime`** (`eclipse-temurin:21-jre-alpine`). Recebe apenas o `.jar` pronto. O JDK, o Maven, o repositório local do Maven e o código-fonte ficam para trás, no primeiro estágio: a imagem final é menor e tem menos coisa para ser atacada.

| Instrução | Por quê |
|---|---|
| `RUN addgroup` e `adduser` + `USER guardario` | a aplicação roda com um usuário de sistema, sem senha, sem shell e sem home. Se alguém explorar uma falha da API, não cai como root |
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

Do computador ou do Cloud Shell, para a VM não gastar crédito parada:

```bash
az vm deallocate --resource-group rg-guardario --name vm-guardario
az vm start      --resource-group rg-guardario --name vm-guardario
```

O IP público é fixo e os containers têm `restart: unless-stopped`: depois do `az vm start`, a API volta no mesmo endereço sem ninguém entrar na VM.

Para apagar tudo depois da apresentação: `./scripts/remover-recursos.sh`.

## Segurança

- Nenhuma senha ou chave no repositório. O `.env` está no `.gitignore` e é gerado na VM com permissão 600.
- Os dois containers rodam sem root: `guardario` (uid 1001) na API e `postgres` (uid 70) no banco.
- O banco não é acessível pela internet: a porta 5432 fica só no loopback da VM e o NSG não a libera.
- O SSH da VM aceita só chave, sem senha.
- A carga de demonstração, que tem usuários com senha conhecida, fica desligada na nuvem.
- O Swagger fica ligado para a demonstração; para desligar, `SWAGGER_ENABLED=false` no `.env` e `docker compose up -d`.

## Problemas comuns

| Sintoma | Causa provável e saída |
|---|---|
| `az vm create` falha com `SkuNotAvailable` ou erro de política de região | a assinatura não oferece o tamanho ou a região. Rode com `LOCATION=eastus` ou outro `VM_SIZE` |
| `permission denied` ao rodar `docker` na VM | o grupo `docker` ainda não vale na sessão: `newgrp docker` ou saia e entre de novo por ssh |
| `docker compose up` para com `Defina POSTGRES_PASSWORD no .env` | falta o `.env`: `./scripts/gerar-env.sh` |
| O navegador não abre `http://IP-PUBLICO:8080` | confira `docker compose ps` (os dois `healthy`) e a regra da 8080 no NSG: `az network nsg rule list -g rg-guardario --nsg-name nsg-guardario -o table` |
| A API reinicia sem parar | o motivo está em `docker compose logs api`. Confira primeiro o `.env`: a `JWT_SECRET` precisa de 32 caracteres ou mais e a `ADMIN_PASSWORD`, de 8 |
| Login do ADMIN dá 401 depois de trocar `ADMIN_PASSWORD` no `.env` | o ADMIN é criado só uma vez, na primeira subida. A senha que vale é a daquela subida |

## Uso de IA generativa

Este projeto usou o Claude (Anthropic) como apoio para organizar a infraestrutura, escrever e revisar os scripts, o Dockerfile, o Compose e este README. Todo o conteúdo foi revisado, executado na VM e é explicado pelos integrantes do grupo. As decisões de arquitetura e os testes foram validados pela equipe.
