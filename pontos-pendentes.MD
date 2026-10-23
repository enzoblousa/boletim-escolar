# Pontos pendentes: Entrega A2 (05/11)

Checklist do que faltava neste repositório para atender a **Avaliação A2 — Projeto Fase 2: Infraestrutura como Código (IaC) e Entrega Contínua (CD)**, conforme `specsEntregaA2`.

> **Status em 23/10/2026:** todos os itens técnicos foram implementados e validados no GitHub Actions. Resta só 1 item manual opcional, marcado com 👤.

## Resumo

| # | Entrega exigida | Situação | Onde |
|---|---|---|---|
| 1 | Dockerfile otimizado | ✅ Feito | `Dockerfile`, `Documentation/DOCKERFILE.md` |
| 2 | Orquestração local (Docker Compose) com dependências | ✅ Feito | `docker-compose.yml`, `Documentation/DOCKER-COMPOSE.md` |
| 3 | Pipeline de CD (push para registry + deploy automático) | ✅ Feito | `.github/workflows/ci-cd.yml`, `deploy.yml`, `Documentation/CI-CD.md` |
| 4 | Gestão segura de configurações e segredos | ✅ Feito | GitHub Environments, `.env.example`, `Documentation/SEGREDOS.md` |
| 5 | Versionamento semântico + rollback documentado | ✅ Feito | tags `v1.0.0` → `v1.1.1`, `Documentation/VERSIONAMENTO-E-ROLLBACK.md` |

---

## 1. Dockerfile otimizado

- [x] **Cache de camadas:** `*.sln`, `global.json` e `*.csproj` copiados primeiro, depois `dotnet restore`, só então `COPY src/` + `dotnet publish --no-restore`.
- [x] **Usuário não-root:** `USER $APP_UID` (uid 1654, usuário `app`).
- [x] **Healthcheck:** endpoint `GET /health` (testa o banco) + `HEALTHCHECK` no Dockerfile.
- [x] **Versão na imagem:** `ARG VERSION`/`REVISION` + labels OCI (`version`, `revision`, `source`).
- [x] Publicar com `-p:UseAppHost=false`.
- [x] Runtime `aspnet:8.0-alpine`: imagem final de ~51 MB comprimida.
- [x] `Documentation/DOCKERFILE.md` atualizado.

## 2. Orquestração local com dependências

- [x] Banco **PostgreSQL 16** com **EF Core 8** / Npgsql.
  - [x] `AppDbContext` + entidade `Aluno` mapeada (`src/MediaEscolar.Api/Data/AppDbContext.cs`).
  - [x] Criação do schema na inicialização (`EnsureCreated`). Migrations ficaram como próximo passo (ver lições em `VERSIONAMENTO-E-ROLLBACK.md`).
  - [x] `List<Aluno>` em memória e `proximoId++` substituídos pelo banco.
  - [x] Connection string via `ConnectionStrings__Default` (variável de ambiente).
- [x] `/health` verificando a conexão com o banco (`AddDbContextCheck<AppDbContext>`).
- [x] Testes de integração com EF Core InMemory (`tests/MediaEscolar.Tests/ApiFactory.cs`), mais testes novos de `/health` e `/version` (9 testes no total).
- [x] **`docker-compose.yml`**:
  - [x] `db` (`postgres:16-alpine`) com volume `db-data` e healthcheck `pg_isready`.
  - [x] `api` (`${APP_IMAGE}:${APP_VERSION}` ou build local), `depends_on: condition: service_healthy`, porta `8080`.
  - [x] Credenciais via `${VARIAVEIS}`, e o compose recusa subir sem `POSTGRES_PASSWORD`.
- [x] Documentado no README, em `Documentation/ComandosParaRodar.md` e em `Documentation/DOCKER-COMPOSE.md`.

## 3. Pipeline de CD automatizado

- [x] Lint + testes primeiro; publish só com CI verde (`needs:`).
- [x] Publicação no **GHCR** (`ghcr.io/enzoblousa/boletim-escolar`):
  - [x] `permissions: packages: write` só no job `publish`
  - [x] `docker/login-action` com `GITHUB_TOKEN`
  - [x] `docker/metadata-action` (tags `X.Y.Z`, `X.Y`, `latest`, `sha-…`)
  - [x] `docker/build-push-action` com cache `gha`
- [x] **`deploy-homologacao`** (Environment `homologacao`): imagem do GHCR + compose + smoke test + rollback automático.
- [x] **`deploy-producao`** (Environment `producao`, com *required reviewer*): mesmo processo.
- [x] Ambiente "simulado": **opção A**, no próprio runner do Actions, partindo da última release estável.
- [x] Evidências mantidas (screenshot Playwright, relatórios, artifact `evidencias-pipeline`), e o e2e do CI agora roda com PostgreSQL.
- [x] Workflow renomeado para `CI-CD`; `Documentation/CI.md` virou `Documentation/CI-CD.md`.
- [x] Job `release` cria a GitHub Release depois de produção.
- [x] Actions atualizadas para versões em Node 24.

## 4. Gestão segura de configurações e segredos

- [x] **Secrets** por Environment: `POSTGRES_PASSWORD` (senhas aleatórias, diferentes entre homologação e produção).
- [x] **Variables** por Environment: `POSTGRES_DB`, `POSTGRES_USER`, `ASPNETCORE_ENVIRONMENT`.
- [x] `.env.example` versionado, sem valores sensíveis.
- [x] `.env` no `.gitignore` e no `.dockerignore`.
- [x] Workflow injeta os secrets como variáveis de ambiente do job (`secrets: inherit` no reusable workflow) e valida a presença deles.
- [x] `appsettings*.json` sem senha nem connection string.
- [x] Senha do banco de CI gerada na hora (`openssl rand`).
- [x] Documentado em `Documentation/SEGREDOS.md`.
- [ ] 👤 Print da tela *Settings → Environments* (secrets listados sem valor), se o professor pedir evidência visual.

## 5. Versionamento semântico e rollback

- [x] **SemVer** com tags `vX.Y.Z`; o push da tag dispara build/push/deploy.
- [x] Imagem com tags `X.Y.Z`, `X.Y`, `latest`, `sha-<commit>`.
- [x] `<Version>` no `.csproj` (sobrescrita pela tag) e `GET /version`, conferido pelo smoke test.
- [x] **GitHub Releases** criadas automaticamente (`v1.0.1`, `v1.1.1`).
- [x] `latest` promovido só depois de produção (corrigido após a `v1.1.0` defeituosa ter virado `latest`).
- [x] Rollback:
  - [x] Automático: smoke test falhou, volta para a versão que estava no ar.
  - [x] Manual: `workflow_dispatch` do workflow `Deploy` com `ambiente` + `versao`.
- [x] **Simulação documentada** em `Documentation/VERSIONAMENTO-E-ROLLBACK.md`, com links das runs:
  1. `v1.0.1` publicada e implantada em homologação e produção.
  2. `v1.1.0` com falha proposital (coluna `Email` sem migration).
  3. Deploy falhou no smoke test de homologação.
  4. Rollback automático para `1.0.1`, com dados preservados e produção intacta.
  5. Rollback manual de produção `1.0.1 → 1.0.0`.
  6. `v1.1.1` com a correção, promovida até produção.

---

## Inconsistências corrigidas

- [x] Badge e links de Actions apontavam para `RED_Ensino_Domiciliar` e agora apontam para `boletim-escolar`.
- [x] O README chamava a esteira de "CI/CD" sem ter CD; agora o CD existe e está documentado.
- [x] Links do README para `Documentation/...` corrigidos.
- [x] Conclusão do README reescrita (sem a referência à "simulada acima").
- [x] `RESULTADOS-TESTES.md`: `coveragereport/` descrito como gerado localmente, não commitado.
- [x] `ComandosParaRodar.md`: URLs `http://localhost:8080`, body do `POST /alunos` só com `nome`, resposta do `GET /alunos/1` como objeto com `media`/`situacao`, `--logger`.
- [x] `.dockerignore`: `docs/` corrigido para `Documentation/`, e `.env`, `scripts/` e compose ignorados.
- [x] Frase incorreta do `CI.md` sobre o .NET no `ubuntu-latest` removida na reescrita (`CI-CD.md`).
- [x] `specsEntregaA2` commitado.
- [x] `TECNOLOGIAS.md` e `EXTENSOES.md` atualizados (PostgreSQL, EF Core, Compose, GHCR, Environments/Secrets, actions do Docker, scripts).

## Pendências manuais (👤)

- [x] Pacote do GHCR público: o `docker pull ghcr.io/enzoblousa/boletim-escolar:latest` funciona sem login (validado em 23/10).
- [ ] 👤 Print da tela de Environments/Secrets (item 4), se necessário.
