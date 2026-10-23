# Dockerfile: explicação e otimizações

O `Dockerfile` da raiz builda a API (`MediaEscolar.Api`) com **multi-stage build**. Um estágio só compila, com o SDK completo do .NET; o outro só roda, com o runtime ASP.NET em **Alpine**. A imagem final não carrega nada do SDK, do código-fonte nem dos testes.

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY MediaEscolar.sln global.json ./
COPY src/MediaEscolar.Api/MediaEscolar.Api.csproj src/MediaEscolar.Api/
COPY tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj tests/MediaEscolar.Tests/
RUN dotnet restore src/MediaEscolar.Api/MediaEscolar.Api.csproj
COPY src/ src/
ARG VERSION
RUN dotnet publish src/MediaEscolar.Api/MediaEscolar.Api.csproj -c Release -o /app --no-restore \
    -p:UseAppHost=false ${VERSION:+-p:Version=$VERSION}

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS final
ARG VERSION=dev
ARG REVISION=local
LABEL org.opencontainers.image.title="media-escolar-api" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.source="https://github.com/enzoblousa/boletim-escolar"
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
USER $APP_UID
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["dotnet", "MediaEscolar.Api.dll"]
```

## Otimizações aplicadas

| Otimização | O que faz | Ganho |
|---|---|---|
| **Cache de restore** | Copia primeiro só `*.sln`, `global.json` e `*.csproj`, roda `dotnet restore` e só depois copia `src/`. | Mudanças no código não invalidam a camada de restore: os pacotes NuGet não são baixados de novo a cada build. |
| **`--no-restore`** no publish | Reaproveita o restore da camada anterior. | Build mais rápido. |
| **Runtime Alpine** (`aspnet:8.0-alpine`) | Base mínima. | Imagem final de **~51 MB comprimida** (~168 MB em disco). Só a base Debian `aspnet:8.0` já tem ~90 MB comprimida (~321 MB em disco), contra ~48 MB (~158 MB) da Alpine. Menos pacotes significa menos superfície de ataque. |
| **`UseAppHost=false`** | Não gera o executável nativo, só a DLL (o `ENTRYPOINT` usa `dotnet`). | Menos arquivos na imagem. |
| **Usuário não-root** (`USER $APP_UID`) | Roda como o usuário `app` (uid 1654), que já vem na imagem oficial. | Mesmo que a aplicação seja comprometida, o processo não tem privilégio de root no container. |
| **`HEALTHCHECK`** | O Docker consulta `/health` (que testa a conexão com o PostgreSQL) a cada 10s. | O `docker compose ps` mostra `healthy`/`unhealthy`, e o deploy espera a aplicação estar saudável. |
| **Versão e labels OCI** (`ARG VERSION` / `REVISION`) | A versão da tag git vira a `<Version>` do assembly (exposta em `GET /version`) e as labels da imagem. | Rastreabilidade: dá para saber qual versão e qual commit estão rodando. O label `source` liga a imagem do GHCR ao repositório. |
| **`.dockerignore`** | Exclui `bin/`, `obj/`, `.git`, `.github`, documentação, scripts, `TestResults/` e **`.env`**. | Contexto de build menor, e segredos locais nunca entram na imagem. |

## Estágio 1: `build`

- **`FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build`**: imagem do SDK, com compilador, NuGet e `dotnet publish`. É pesada e só existe para compilar.
- **`COPY` dos arquivos de projeto + `RUN dotnet restore`**: camada de dependências, que fica em cache enquanto os `.csproj` não mudarem. O `.csproj` de testes entra só porque a `.sln` o referencia; o código dos testes não é copiado.
- **`COPY src/ src/`**: código-fonte da API, a camada que muda a cada commit.
- **`ARG VERSION` + `dotnet publish`**: compila em `Release`. Se `VERSION` vier do pipeline (`1.2.3`), sobrescreve a `<Version>` do csproj. Sem ela, vale a versão do csproj.

## Estágio 2: `final` (runtime)

- **`FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine`**: só o runtime ASP.NET Core.
- **`LABEL`**: metadados OCI (versão, commit, repositório de origem).
- **`COPY --from=build /app .`**: só o resultado compilado atravessa de um estágio para o outro.
- **`ENV ASPNETCORE_URLS=http://+:8080`** e **`EXPOSE 8080`**: a API escuta na porta 8080. A publicação da porta no host é feita no `docker run -p` ou no `docker-compose.yml`.
- **`USER $APP_UID`**: processo sem privilégios.
- **`HEALTHCHECK`**: `wget` (do busybox do Alpine) em `/health`.
- **`ENTRYPOINT ["dotnet", "MediaEscolar.Api.dll"]`**: inicia a API.

## Comandos

```bash
docker build -t media-escolar .                                   # versão do csproj
docker build --build-arg VERSION=1.2.3 -t media-escolar:1.2.3 .   # versão explícita (o que o pipeline faz)
docker image inspect media-escolar:1.2.3 --format '{{json .Config.Labels}}'
```

> A API depende de PostgreSQL. Para rodar, use o `docker compose` ([`DOCKER-COMPOSE.md`](DOCKER-COMPOSE.md)). Um `docker run` sozinho, sem banco, deixa o container `unhealthy`.
