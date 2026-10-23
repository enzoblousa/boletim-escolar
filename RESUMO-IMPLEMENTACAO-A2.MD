# Resumo da implementação: Entrega A2 (IaC + CD)

Registro do que foi feito nesta sessão (23/10/2026) para atender ao `specsEntregaA2`, para consulta posterior.
O checklist item a item está em [`pontos-pendentes.MD`](pontos-pendentes.MD). Os detalhes técnicos estão na pasta [`Documentation/`](Documentation/).

**Status final:** os 5 itens da A2 estão implementados e funcionando no GitHub Actions, e a `main` está com o CI verde. O registry usado é o do GitHub (GHCR).

---

## 1. O que foi entregue

| # | Entrega | Como ficou | Onde ver |
|---|---|---|---|
| 1 | **Dockerfile otimizado** | Restore separado em cache, imagem final Alpine de ~51 MB (antes ~90 MB só a base Debian), roda sem root (usuário `app`), tem `HEALTHCHECK` e versão gravada na imagem (labels OCI). | `Dockerfile`, `Documentation/DOCKERFILE.md` |
| 2 | **Docker Compose** | A API agora usa **PostgreSQL 16** via EF Core (antes guardava os alunos só em memória). Ganhou os endpoints `/health` (testa o banco) e `/version`. O `docker-compose.yml` sobe API + banco, com healthchecks, `depends_on` e volume. | `docker-compose.yml`, `.env.example`, `Documentation/DOCKER-COMPOSE.md` |
| 3 | **CD com GHCR** | Cada tag `vX.Y.Z` roda o CI, publica a imagem em `ghcr.io/enzoblousa/boletim-escolar`, faz deploy em homologação e depois em produção (com aprovação manual) e cria a GitHub Release. | `.github/workflows/ci-cd.yml`, `.github/workflows/deploy.yml`, `Documentation/CI-CD.md` |
| 4 | **Secrets** | Ambientes `homologacao` e `producao` no GitHub, com Secrets (`POSTGRES_PASSWORD`, senhas aleatórias diferentes) e Variables (`POSTGRES_DB`, `POSTGRES_USER`, `ASPNETCORE_ENVIRONMENT`). Localmente se usa um `.env`, que fica fora do git. O registry usa o `GITHUB_TOKEN` efêmero. Nenhuma senha está no código. | `Documentation/SEGREDOS.md` |
| 5 | **Versão e rollback** | Tags `v1.0.0` até `v1.1.1`, propagadas para a imagem, o `GET /version` e as Releases. Rollback automático quando o smoke test falha e rollback manual pelo workflow `Deploy`. | `scripts/deploy.sh`, `scripts/smoke-test.sh`, `Documentation/VERSIONAMENTO-E-ROLLBACK.md` |

### Arquivos novos ou alterados

- **Aplicação:** `src/MediaEscolar.Api/Program.cs`, `Data/AppDbContext.cs`, `MediaEscolar.Api.csproj` (EF Core + Npgsql + Health Checks, `<Version>`).
- **Testes:** `tests/MediaEscolar.Tests/ApiFactory.cs` (troca o PostgreSQL por EF InMemory nos testes), testes novos de `/health` e `/version`. São 9 testes no total, todos passando.
- **Infra:** `Dockerfile`, `.dockerignore`, `docker-compose.yml`, `.env.example`, `.gitignore` (agora ignora o `.env`).
- **Pipeline:** `.github/workflows/ci-cd.yml` (antigo `ci.yml`) e `.github/workflows/deploy.yml` (workflow reutilizável + disparo manual).
- **Scripts:** `scripts/smoke-test.sh` (health + versão + fluxo completo) e `scripts/deploy.sh` (deploy com rollback automático).
- **Docs:** `README.md`, `Documentation/CI-CD.md` (antigo `CI.md`), `DOCKERFILE.md`, `DOCKER-COMPOSE.md`, `SEGREDOS.md`, `VERSIONAMENTO-E-ROLLBACK.md`, `ComandosParaRodar.md`, `RESULTADOS-TESTES.md`, `TECNOLOGIAS.md`, `EXTENSOES.md`.

### Como o pipeline funciona agora

```
push/PR main ──► build-and-test (lint, testes, build da imagem, e2e com compose + PostgreSQL, screenshot)
tag v1.2.3  ──► build-and-test ──► publish (GHCR) ──► deploy-homologacao ──► [aprovação] deploy-producao ──► release (+ latest)
                                                          │ falhou?                    │ falhou?
                                                          └─► rollback automático      └─► rollback automático
manual      ──► Deploy (workflow_dispatch: ambiente + versão) = rollback manual
```

Os ambientes de homologação e produção são **simulados** no próprio runner do GitHub Actions, com `docker compose`. Para o deploy partir de um estado realista, o workflow primeiro sobe a última versão estável (última GitHub Release) e cria dados. Só então implanta a versão nova por cima.

---

## 2. Simulação de rollback (evidência do item 5)

| # | Versão | O que aconteceu | Run |
|---|---|---|---|
| 1 | `v1.0.0` | Imagem publicada, mas o deploy foi barrado pela validação de configuração: a senha chegou vazia (bug no pipeline, ver seção 3). | [39963183740](https://github.com/enzoblousa/boletim-escolar/actions/runs/39963183740) |
| 2 | `v1.0.1` | Correção do pipeline. Passou por homologação e produção, e a Release foi criada. | [39964205758](https://github.com/enzoblousa/boletim-escolar/actions/runs/39964205758) |
| 3 | `v1.1.0` | **Defeito proposital**: campo `Email` novo sem migration. Passou nos testes e no CI, mas falhou em homologação com `column "Email" does not exist`. **Rollback automático para a 1.0.1**, com os dados do banco preservados. Produção não foi tocada e não houve Release. | [39965267691](https://github.com/enzoblousa/boletim-escolar/actions/runs/39965267691) |
| 4 | — | Revert do defeito na `main` (PR #4). | — |
| 5 | `1.0.0` | **Rollback manual** de produção (`1.0.1 → 1.0.0`) pelo workflow `Deploy`, com aprovação. | [39966010445](https://github.com/enzoblousa/boletim-escolar/actions/runs/39966010445) |
| 6 | `v1.1.1` | Correção publicada. Passou por homologação e produção, foi criada a Release e o `latest` passou a apontar para a 1.1.1. | [39966956719](https://github.com/enzoblousa/boletim-escolar/actions/runs/39966956719) |

**Por que o defeito da `v1.1.0` só apareceu em homologação:** os testes usam um banco em memória criado do zero, e o CI usa um PostgreSQL novo e vazio. Nos dois casos a coluna nasce junto com a tabela. Em homologação a tabela `alunos` já existia, e o `EnsureCreated()` não altera tabelas existentes. A lição registrada é usar migrations do EF Core para mudanças de schema.

---

## 3. Problemas encontrados no caminho (todos corrigidos)

1. **`v1.0.0` não chegou a ser implantada.** O deploy é um workflow reutilizável, e nesse caso os secrets precisam ser repassados com `secrets: inherit`. Sem isso, o `POSTGRES_PASSWORD` chegava vazio, e a validação que eu tinha colocado barrou o deploy antes de subir qualquer coisa. Corrigi (PR #2) e publiquei a `v1.0.1`. Aproveitei para atualizar as actions para as versões em Node 24, o que removeu o aviso de depreciação do Node 20.
2. **A tag `latest` chegou a apontar para a `1.1.0` defeituosa.** O `docker/metadata-action` movia o `latest` em toda tag, mesmo que a versão depois falhasse no deploy. Como o compose usa `latest` por padrão, quem subisse localmente pegaria a versão quebrada. Agora o `latest` só é movido no job `release`, depois de produção (PR #5).
3. **Duas runs travaram por mais de 10 minutos** no `playwright install --with-deps`, por causa de lentidão no espelho apt do runner. Agora o screenshot usa o Google Chrome que já vem instalado no runner (`--channel chrome`), e todos os jobs têm `timeout-minutes` (PR #7). O passo de e2e caiu de mais de 10 min para ~30 s.
4. **Erro meu: o PR #6 foi mergeado com o CI cancelado.** Meu comando encadeado fazia o merge sem checar o resultado da run. Ele só mexia em 2 arquivos `.md`, e o CI da `main` passou depois. A partir dali, só fiz merge com o CI verde.

---

## 4. Ações feitas no GitHub em seu nome (autorizadas na sessão)

- Criação dos Environments `homologacao` e `producao`: produção com aprovação manual (reviewer `enzoblousa`), e os dois restritos a tags `v*` e à branch `main`.
- Criação dos Secrets (senhas aleatórias, nunca exibidas) e das Variables de cada Environment.
- PRs #1 a #7 abertos e mergeados na `main`.
- Tags `v1.0.0`, `v1.0.1`, `v1.1.0` e `v1.1.1` enviadas.
- **Aprovação dos deploys de produção** usando o seu login do `gh`.
- Disparo do rollback manual de produção para a `1.0.0`.

O pacote no GHCR já é público: testei baixar a `latest` sem login, subi com o compose e o smoke test passou na `1.1.1`.

---

## 5. O que ainda depende de você

- [ ] Se o professor pedir evidência visual dos segredos, tirar um print de *Settings → Environments* (os secrets aparecem listados sem o valor).
- [ ] Na apresentação ao vivo, subir sempre com `docker compose up`. Um `docker run` sozinho, sem o banco, deixa o container `unhealthy`.

### Comandos úteis para a apresentação

```bash
cp .env.example .env                          # preencha POSTGRES_PASSWORD
docker compose up -d --build                  # sobe API + PostgreSQL (build local)
APP_VERSION=1.1.1 docker compose up -d --no-build   # ou: usa a imagem publicada no GHCR
./scripts/smoke-test.sh                       # health + versão + fluxo completo
./scripts/deploy.sh 1.0.1                     # deploy/rollback local com smoke test

git tag -a v1.2.0 -m "..." && git push origin v1.2.0      # nova release (dispara o CD)
gh workflow run deploy.yml -f ambiente=producao -f versao=1.1.1   # rollback manual
```

### Links

- Actions: https://github.com/enzoblousa/boletim-escolar/actions
- Imagens no GHCR: https://github.com/enzoblousa/boletim-escolar/pkgs/container/boletim-escolar
- Releases: https://github.com/enzoblousa/boletim-escolar/releases
- Histórico de deploys: https://github.com/enzoblousa/boletim-escolar/deployments
