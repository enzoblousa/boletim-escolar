# `docker-compose.yml`: orquestração local

Sobe a API integrada com a sua dependência, o **PostgreSQL**. O mesmo arquivo é usado em três lugares: na máquina local, no teste end-to-end do CI e no deploy simulado de homologação/produção (`scripts/deploy.sh`).

## Serviços

| Serviço | Imagem | Papel |
|---|---|---|
| `db` | `postgres:16-alpine` | Banco de dados. Dados persistidos no volume nomeado `db-data`. Healthcheck com `pg_isready`. |
| `api` | `${APP_IMAGE}:${APP_VERSION}` (padrão `ghcr.io/enzoblousa/boletim-escolar:latest`), ou build local do `Dockerfile` | API. Só inicia depois que o banco estiver **healthy** (`depends_on: condition: service_healthy`). Healthcheck próprio via `HEALTHCHECK` do Dockerfile (`GET /health`, que testa a conexão com o banco). |

Os dois serviços usam `restart: unless-stopped`. O banco não expõe porta para fora da rede do compose: só a API (`${APP_PORT:-8080}:8080`) fica acessível.

## Variáveis

Todas vêm do `.env` (local) ou dos Secrets/Variables do GitHub (pipeline). Ver [`SEGREDOS.md`](SEGREDOS.md) e o `.env.example`.

| Variável | Padrão | Uso |
|---|---|---|
| `POSTGRES_PASSWORD` | **obrigatória** | senha do banco (o compose não sobe sem ela) |
| `POSTGRES_USER` / `POSTGRES_DB` | `media_escolar` | usuário e nome do banco |
| `APP_IMAGE` / `APP_VERSION` | `ghcr.io/enzoblousa/boletim-escolar` / `latest` | qual imagem/versão da API subir |
| `APP_PORT` | `8080` | porta publicada no host |
| `ASPNETCORE_ENVIRONMENT` | `Production` | ambiente do ASP.NET Core |

## Comandos

```bash
cp .env.example .env                 # preencha POSTGRES_PASSWORD
docker compose up -d --build         # builda a imagem local e sobe API + banco
docker compose ps                    # os dois devem ficar "healthy"
./scripts/smoke-test.sh              # health + versão + fluxo completo
docker compose logs -f api           # logs da API
docker compose down                  # para tudo (mantém os dados no volume)
docker compose down -v               # para tudo e APAGA os dados
```

Para subir uma versão já publicada no GHCR, sem build:

```bash
APP_VERSION=1.0.0 docker compose up -d --no-build
```

## Criação do schema

A API chama `Database.EnsureCreated()` na inicialização e cria a tabela `alunos` se ela não existir. Esse mecanismo **não altera** uma tabela que já existe. Essa limitação foi justamente a causa da falha simulada da `v1.1.0` (ver [`VERSIONAMENTO-E-ROLLBACK.md`](VERSIONAMENTO-E-ROLLBACK.md)).
