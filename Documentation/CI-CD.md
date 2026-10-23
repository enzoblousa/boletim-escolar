# Pipeline CI/CD — `.github/workflows/ci-cd.yml` e `deploy.yml`

A esteira tem duas partes:

- **CI** (todo push/PR para `main` e toda tag): lint, testes com cobertura, build da imagem e teste end-to-end da imagem real com PostgreSQL via `docker compose`.
- **CD** (só tags semver `vX.Y.Z`): publica a imagem no **GitHub Container Registry (GHCR)**, faz deploy em **homologação**, depois em **produção** (com aprovação manual) e cria a **GitHub Release**. Se o deploy falhar, um **rollback automático** traz de volta a versão anterior.

```
push/PR main ──► build-and-test
tag v1.2.3  ──► build-and-test ──► publish (GHCR) ──► deploy-homologacao ──► [aprovação] deploy-producao ──► release
                                                         │ falhou?                   │ falhou?
                                                         └─► rollback automático     └─► rollback automático
manual      ──► Deploy (workflow_dispatch: ambiente + versão)  = rollback manual
```

## Gatilhos

```yaml
on:
  push:
    branches: [ main ]
    tags: [ 'v*.*.*' ]
  pull_request:
    branches: [ main ]
```

- Push/PR para `main` → só o job `build-and-test` (CI).
- Push de uma tag como `v1.2.3` → CI + CD completo. A tag é o "botão" de release: versão semântica e deploy andam juntos.

## Job `build-and-test` (CI)

1. **Checkout** e **Setup .NET 8**.
2. **Restore** das dependências da solução.
3. **Análise estática**: `dotnet format style` e `dotnet format analyzers` com `--verify-no-changes`, gerando `format-report.json`. A categoria `whitespace` continua fora do gate, porque o repositório não tem `.editorconfig`.
4. **Testes com cobertura** (`dotnet test` + coverlet). Os testes de integração usam a API real em memória (`WebApplicationFactory`), com o PostgreSQL trocado por EF Core InMemory (`tests/MediaEscolar.Tests/ApiFactory.cs`).
5. **Build da imagem Docker**. Se o push for uma tag, a versão é passada para a imagem (`v1.2.3` → `--build-arg VERSION=1.2.3`).
6. **Teste end-to-end com docker compose**: sobe a imagem buildada junto com um PostgreSQL real e roda `scripts/smoke-test.sh`. O smoke test verifica `/health`, `/version` e o fluxo cadastro → notas → consulta. Depois o Playwright tira o screenshot `screenshot-execucao.png` do `GET /alunos/1`. A senha desse banco descartável é gerada na hora com `openssl rand`, então não há senha no código.
7. **Encerrar containers** (`docker compose down -v`, sempre roda).
8. **Publicar evidências**: o artifact `evidencias-pipeline` traz o relatório do linter, o `.trx`, a cobertura e o screenshot.

## Job `publish` (CD: Container Registry)

Roda só em tags `v*`, depois do CI verde. Permissão `packages: write`.

- `docker/login-action`: login no `ghcr.io` com o `GITHUB_TOKEN`, um token efêmero que o Actions gera a cada execução, sem nenhuma credencial salva.
- `docker/metadata-action`: gera as tags da imagem a partir da tag git:
  - `ghcr.io/enzoblousa/boletim-escolar:1.2.3` (versão exata, imutável)
  - `ghcr.io/enzoblousa/boletim-escolar:1.2` (última patch da minor)
  - `ghcr.io/enzoblousa/boletim-escolar:sha-<commit>` (rastreabilidade)
- `docker/build-push-action`: build + push, com cache de camadas do GitHub Actions (`type=gha`) e os build-args `VERSION`/`REVISION`, que viram labels OCI e a resposta de `GET /version`.

## Jobs `deploy-homologacao` e `deploy-producao` (CD: deploy)

Os dois chamam o workflow reutilizável `.github/workflows/deploy.yml` com `ambiente` e `versao`.

O **ambiente é simulado** no próprio runner do GitHub Actions, uma VM efêmera, com `docker compose`: API + PostgreSQL, igual ao ambiente local. Cada ambiente é um **GitHub Environment**:

| Environment | Proteção | Secrets | Variables |
|---|---|---|---|
| `homologacao` | só tags `v*` e `main` | `POSTGRES_PASSWORD` | `POSTGRES_DB=media_escolar_hml`, `POSTGRES_USER`, `ASPNETCORE_ENVIRONMENT=Staging` |
| `producao` | **aprovação manual (required reviewer)** + só tags `v*` e `main` | `POSTGRES_PASSWORD` (senha diferente) | `POSTGRES_DB=media_escolar`, `POSTGRES_USER`, `ASPNETCORE_ENVIRONMENT=Production` |

Passos do `deploy.yml`:

1. **Validar configuração**: falha se o secret `POSTGRES_PASSWORD` não existir no Environment.
2. **Login no GHCR** (`packages: read`) para baixar a imagem publicada.
3. **Restaurar estado atual do ambiente**: como o runner nasce vazio, primeiro sobe a **última GitHub Release** (última versão estável) e roda o smoke test nela. Assim o deploy parte de um ambiente "em produção" com banco e dados já existentes, e não de um ambiente vazio.
4. **Deploy com rollback automático** (`scripts/deploy.sh <versao>`):
   - lê a versão que está no ar (`GET /version`);
   - sobe a nova versão e roda o smoke test;
   - se falhar, mostra os logs, **volta para a versão anterior** e roda o smoke test de novo;
   - termina com erro (job vermelho) sempre que a nova versão não foi aceita, mesmo que o rollback tenha dado certo. Assim produção e Release não acontecem.
5. **Estado final**: mostra a versão no ar e os containers.

## Job `release`

Só roda se **homologação e produção** passarem. Faz duas coisas:

1. **Promove a imagem para `latest`** (`docker buildx imagetools create`, um retag do manifest sem rebuild). O `latest` sempre aponta para a última versão que passou em produção, nunca para uma versão recém-publicada que ainda pode falhar. Antes dessa correção, o `metadata-action` movia o `latest` já no `publish`, e a `v1.1.0` defeituosa chegou a virar `latest` mesmo barrada em homologação.
2. Cria a GitHub Release da tag com notas geradas automaticamente. A última Release é a referência de "versão estável" usada no passo 3 do deploy e nos rollbacks.

## Rollback manual

`Actions → Deploy → Run workflow`, escolhendo `ambiente` e `versao` (ex.: `producao` / `1.0.0`). Pela CLI:

```bash
gh workflow run deploy.yml -f ambiente=producao -f versao=1.0.0
```

Detalhes e a simulação documentada estão em [`VERSIONAMENTO-E-ROLLBACK.md`](VERSIONAMENTO-E-ROLLBACK.md). A parte de segredos está em [`SEGREDOS.md`](SEGREDOS.md).

## Onde quebra mais fácil

- **`dotnet format`**: problemas de estilo/analisadores.
- **`dotnet test`**: algum teste falhou.
- **Teste end-to-end**: a imagem não sobe, o banco não conecta ou o fluxo retorna algo inesperado.
- **Deploy**: smoke test falhou contra o banco que já existe (ex.: mudança de schema sem migration). Nesse caso entra o rollback automático.
