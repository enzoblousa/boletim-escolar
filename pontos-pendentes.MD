# Pontos pendentes — Entrega A2 (05/11)

Checklist do que falta neste repositório para atender a **Avaliação A2 — Projeto Fase 2: Infraestrutura como Código (IaC) e Entrega Contínua (CD)**, conforme `specsEntregaA2`.

## Resumo

| # | Entrega exigida | Situação atual |
|---|---|---|
| 1 | Dockerfile otimizado | ⚠️ Existe, mas não está otimizado |
| 2 | Orquestração local (Docker Compose ou K8s) com dependências | ❌ Não existe |
| 3 | Pipeline de CD (push para registry + deploy automático) | ❌ Não existe — pipeline atual é só CI |
| 4 | Gestão segura de configurações e segredos | ❌ Nenhum secret/variável de ambiente em uso |
| 5 | Versionamento semântico + rollback documentado | ❌ Sem tags, sem versão na imagem, sem rollback |

---

## 1. Dockerfile otimizado

Arquivo atual: `Dockerfile` (multi-stage `sdk:8.0` → `aspnet:8.0`).

- [ ] **Cache de camadas:** copiar primeiro só `MediaEscolar.sln`, `global.json` e os `.csproj`, rodar `dotnet restore` e só depois `COPY . .` + `dotnet publish --no-restore`. Hoje o `COPY . .` invalida o restore a cada mudança de código.
- [ ] **Usuário não-root:** adicionar `USER $APP_UID` no estágio final (o usuário `app` já existe na imagem `aspnet:8.0`).
- [ ] **Healthcheck:** criar endpoint `GET /health` na API e adicionar `HEALTHCHECK` no Dockerfile (ou no compose).
- [ ] **Versão na imagem:** `ARG VERSION` + labels OCI (`org.opencontainers.image.version`, `org.opencontainers.image.source`, `org.opencontainers.image.revision`).
- [ ] Publicar com `-p:UseAppHost=false` (imagem menor, só a DLL é necessária).
- [ ] Atualizar `Documentation/DOCKERFILE.md` com as mudanças.

## 2. Orquestração local com dependências

Hoje a API guarda os alunos em uma `List<Aluno>` em memória (`src/MediaEscolar.Api/Program.cs`) — **não há dependência nenhuma para orquestrar**, e o spec pede integração com banco de dados/cache.

- [ ] Adicionar banco de dados (sugestão: **PostgreSQL** com **EF Core** / `Npgsql.EntityFrameworkCore.PostgreSQL`).
  - [ ] `DbContext` + entidade `Aluno` mapeada.
  - [ ] Migrations (ou `EnsureCreated`/`Migrate` na inicialização).
  - [ ] Substituir a `List<Aluno>` e o `proximoId++` (não thread-safe) pelo banco.
  - [ ] Connection string lida de configuração/variável de ambiente (`ConnectionStrings__Default`), nunca fixa no código.
- [ ] `/health` verificando também a conexão com o banco (`AddHealthChecks().AddNpgSql(...)` ou `AddDbContextCheck`).
- [ ] Ajustar `tests/MediaEscolar.Tests/ApiIntegrationTests.cs` para não depender de um Postgres real (SQLite in-memory / EF InMemory via `WebApplicationFactory.ConfigureServices`, ou Testcontainers).
- [ ] Criar **`docker-compose.yml`** na raiz:
  - [ ] serviço `db` (`postgres:16-alpine`) com volume nomeado e `healthcheck` (`pg_isready`).
  - [ ] serviço `api` (build local ou `image: ghcr.io/enzoblousa/boletim-escolar:${APP_VERSION}`), `depends_on: db: condition: service_healthy`, porta `8080:8080`.
  - [ ] Todas as credenciais vindas de `${VARIAVEIS}` (ver item 4).
- [ ] Documentar como subir: `docker compose up -d --build` (README + `Documentation/ComandosParaRodar.md`).

## 3. Pipeline de CD automatizado

Arquivo atual: `.github/workflows/ci.yml` — só builda a imagem localmente com a tag `media-escolar` e nunca publica.

- [ ] Reordenar: lint + testes primeiro; build/push da imagem **só se passarem** (job separado com `needs:`).
- [ ] Publicar a imagem no **GHCR** (`ghcr.io/enzoblousa/boletim-escolar`):
  - [ ] `permissions: packages: write`
  - [ ] `docker/login-action` (usando `GITHUB_TOKEN`)
  - [ ] `docker/metadata-action` (gera tags semver + `sha`)
  - [ ] `docker/build-push-action`
- [ ] Job **`deploy-homologacao`** (GitHub Environment `homologacao`): baixa a imagem publicada do registry, sobe com `docker compose`, roda smoke test (`/health` + fluxo cadastro → notas → consulta).
- [ ] Job **`deploy-producao`** (GitHub Environment `producao`, com *required reviewers* para aprovação manual), mesmo processo.
- [ ] Decidir o ambiente "simulado":
  - Opção A (gratuita, sem conta externa): deploy no próprio runner do Actions via compose + smoke test.
  - Opção B: serviço real (Render/Railway) acionado via deploy hook guardado em secret.
- [ ] Manter os passos atuais de evidência (screenshot Playwright, relatórios, artifact `evidencias-pipeline`).
- [ ] Renomear o workflow (ex.: `CI-CD`) e atualizar `Documentation/CI.md`.

## 4. Gestão segura de configurações e segredos

- [ ] Criar **GitHub Secrets** (por Environment quando fizer sentido): `POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB` (e o deploy hook, se usar a opção B).
- [ ] Usar **GitHub Variables** para o que não é sensível (ex.: `APP_PORT`, `ASPNETCORE_ENVIRONMENT`).
- [ ] Criar `.env.example` versionado (só nomes das variáveis, sem valores reais).
- [ ] Adicionar `.env` ao `.gitignore` e ao `.dockerignore`.
- [ ] No workflow, gerar o `.env` do deploy a partir dos secrets (`${{ secrets.X }}`) — nunca em texto puro no YAML.
- [ ] Garantir que `appsettings*.json` não contenham senha/connection string real.
- [ ] Documentar quais secrets existem e onde são usados (sem os valores) — print da tela de Secrets como evidência.

## 5. Versionamento semântico e rollback

- [ ] Adotar **SemVer** com tags git `vMAJOR.MINOR.PATCH` (ex.: `v1.0.0`); o push de uma tag `v*` dispara build/push/deploy.
- [ ] Imagem publicada com tags `1.0.0`, `1.0`, `sha-<commit>` (via `docker/metadata-action`).
- [ ] (Opcional) `<Version>` no `MediaEscolar.Api.csproj` e versão exposta no `/health` ou em `GET /version`, para provar qual versão está no ar.
- [ ] Criar **GitHub Releases** para cada tag.
- [ ] Rollback:
  - [ ] Automático: se o smoke test pós-deploy falhar, redeploy da última tag estável.
  - [ ] Manual: `workflow_dispatch` com input `version` para reimplantar qualquer tag publicada.
- [ ] **Simulação documentada** em `Documentation/ROLLBACK.md`:
  1. Publicar `v1.0.0` (funcionando).
  2. Publicar `v1.1.0` com falha proposital (ex.: `/health` retornando 500).
  3. Mostrar o deploy falhando no smoke test.
  4. Mostrar o rollback para `v1.0.0` e a API de volta ao ar.
  5. Anexar links das runs e prints.

---

## Inconsistências já existentes a corrigir

- [ ] Badge do CI, link da run de evidência (`README.md`) e link de Actions (`Documentation/RESULTADOS-TESTES.md`) apontam para `enzoblousa/RED_Ensino_Domiciliar`; o repositório é `enzoblousa/boletim-escolar`.
- [ ] `README.md` chama a esteira de "CI/CD", mas hoje não existe CD.
- [ ] `README.md` linka `RESULTADOS-TESTES.md` na raiz; o arquivo está em `Documentation/RESULTADOS-TESTES.md`.
- [ ] Conclusão do `README.md` cita "regressões (como a simulada acima)", mas essa seção foi removida.
- [ ] `Documentation/RESULTADOS-TESTES.md` diz que `coveragereport/` é commitado como evidência permanente, mas a pasta não existe no repositório (commitar ou remover a afirmação).
- [ ] `Documentation/ComandosParaRodar.md`:
  - [ ] URLs `https//:LocalHost:8080` → `http://localhost:8080` (a imagem não serve HTTPS).
  - [ ] Body do `POST /alunos` envia `id`, `nota1`, `nota2`; a API só aceita `{ "nome": "..." }`.
  - [ ] Exemplo de resposta do `GET /alunos/1` mostra um array com notas `null`; a API retorna um objeto com `media` e `situacao`.
  - [ ] `dotnet test -logger` → `dotnet test --logger`.
- [ ] `.dockerignore` ignora `docs/`, mas a pasta se chama `Documentation/`.
- [ ] `Documentation/CI.md` afirma que o `ubuntu-latest` não vem com .NET; ele vem — o `setup-dotnet` serve para fixar a versão.
- [ ] `specsEntregaA2` ainda não está commitado.
- [ ] Atualizar `Documentation/TECNOLOGIAS.md` com as novas tecnologias (PostgreSQL, EF Core, Docker Compose, GHCR, GitHub Environments/Secrets, actions do Docker).

## Ordem sugerida de execução

1. `/health` + PostgreSQL/EF Core + connection string via ambiente + testes ajustados.
2. Otimização do Dockerfile.
3. `docker-compose.yml` + `.env.example` + `.gitignore`.
4. Workflow de CD: push GHCR com tags semver → deploy homologação → deploy produção, usando secrets.
5. Tag `v1.0.0`, depois `v1.1.0` quebrada, e documentação do rollback.
6. Correção das inconsistências e atualização de README e `Documentation/`.
