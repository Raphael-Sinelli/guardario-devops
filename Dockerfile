# syntax=docker/dockerfile:1

# =====================================================================================
# GuardaRio API · imagem em dois estágios (multi-stage)
#   1) build   : JDK + Maven Wrapper compilam o código e geram o .jar
#   2) runtime : só o JRE (Alpine) e o .jar, rodando com usuário sem privilégio
# O JDK, o Maven e o código-fonte ficam no estágio 1 e não entram na imagem final.
# =====================================================================================

# ---------- Estágio 1: build ----------
FROM eclipse-temurin:21-jdk AS build

WORKDIR /workspace

# Primeiro só o que define as dependências. Enquanto o pom.xml não mudar, o Docker
# reaproveita esta camada do cache e não baixa as dependências de novo a cada build.
COPY api/.mvn/ .mvn/
COPY api/mvnw api/pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -ntp dependency:go-offline

# Agora o código. Os testes (com H2) rodam no desenvolvimento; aqui o build só empacota.
COPY api/src/ src/
RUN ./mvnw -B -ntp clean package -DskipTests

# ---------- Estágio 2: execução ----------
FROM eclipse-temurin:21-jre-alpine AS runtime

LABEL org.opencontainers.image.title="guardario-api" \
      org.opencontainers.image.description="API REST do GuardaRio, alerta comunitário de enchentes (Global Solution 2026/2, FIAP)" \
      org.opencontainers.image.source="https://github.com/Raphael-Sinelli/guardario-devops"

# Usuário e grupo de sistema, sem senha, sem shell de login e sem pasta home.
# Se alguém explorar uma falha da aplicação, cai num usuário que não é root.
RUN addgroup -S -g 1001 guardario \
 && adduser -S -u 1001 -G guardario -H -s /sbin/nologin guardario

WORKDIR /app

# O .jar pertence ao root e o usuário da aplicação só lê: ela não consegue alterar o próprio código.
COPY --from=build /workspace/target/guardario-api-*.jar app.jar

# Padrões da imagem. Senhas e chaves NÃO ficam aqui: chegam pelo docker-compose.yml, lidas do .env.
ENV SPRING_PROFILES_ACTIVE=prod \
    PORT=8080 \
    TZ=UTC \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0"

EXPOSE 8080

USER guardario

# O Docker chama o Actuator: o container só fica "healthy" quando a API e o banco respondem.
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD wget -q -O /dev/null "http://localhost:${PORT}/actuator/health" || exit 1

# Forma exec: o java é o processo 1 do container e recebe o SIGTERM do "docker compose down".
ENTRYPOINT ["java", "-jar", "app.jar"]
