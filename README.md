# API de Média Escolar

![CI-CD](https://github.com/enzoblousa/boletim-escolar/actions/workflows/ci-cd.yml/badge.svg)

## Descrição
API simples para cadastro de alunos, registro de duas notas e cálculo automático da média e da situação (Aprovado/Reprovado). Construída como atividade da disciplina Testes e Qualidade de Software, demonstrando Docker, testes automatizados, Infraestrutura como Código e uma esteira de CI/CD com entrega contínua, versionamento semântico e rollback.

## Tecnologias utilizadas
- Linguagem: C# / .NET 8
- Framework: ASP.NET Core Minimal API + Health Checks
- Persistência: PostgreSQL 16 + Entity Framework Core 8 (Npgsql)
- Ferramenta de testes: xUnit, coverlet (cobertura), Microsoft.AspNetCore.Mvc.Testing + EF Core InMemory (testes de integração)
- Docker: Dockerfile multi-stage otimizado (sdk:8.0 para build, aspnet:8.0-alpine para runtime, usuário não-root, healthcheck)
- Orquestração: Docker Compose (API + PostgreSQL)
- CI/CD: GitHub Actions + GitHub Container Registry (GHCR) + GitHub Environments/Secrets + GitHub Releases

Lista completa em [`Documentation/TECNOLOGIAS.md`](Documentation/TECNOLOGIAS.md).

## Funcionalidades
- Cadastrar aluno (`POST /alunos`)
- Registrar duas notas de um aluno, validadas entre 0 e 10 (`POST /alunos/{id}/notas`)
- Consultar aluno com média e situação calculadas (`GET /alunos/{id}`)
- Listar todos os alunos cadastrados (`GET /alunos`)
- Health check com verificação do banco (`GET /health`)
- Versão semântica em execução (`GET /version`)

## Como executar com Docker Compose

```bash
cp .env.example .env          # preencha POSTGRES_PASSWORD (o .env não vai para o git)
docker compose up -d --build  # builda a imagem e sobe API + PostgreSQL
./scripts/smoke-test.sh       # opcional: verifica health, versão e o fluxo completo
```

A API fica disponível em `http://localhost:8080`. Para subir uma versão já publicada no registry, sem build:

```bash
APP_VERSION=1.0.0 docker compose up -d --no-build
```

Detalhes: [`DOCKER-COMPOSE.md`](Documentation/DOCKER-COMPOSE.md), [`DOCKERFILE.md`](Documentation/DOCKERFILE.md), [`ComandosParaRodar.md`](Documentation/ComandosParaRodar.md).

## Como executar os testes

Localmente (sem Docker e sem banco: os testes de integração usam EF Core InMemory), com o SDK do .NET 8 instalado:

```bash
dotnet test MediaEscolar.sln
```

Onde ficam os resultados (relatório de testes, cobertura, evidências) e como visualizar cada um: [`RESULTADOS-TESTES.md`](Documentation/RESULTADOS-TESTES.md).

## Pipeline CI/CD
Workflows: `.github/workflows/ci-cd.yml` e `.github/workflows/deploy.yml` (detalhes em [`CI-CD.md`](Documentation/CI-CD.md)).

**CI** (todo push/PR para `main` e toda tag):
1. Checkout e setup do .NET 8
2. Análise estática (`dotnet format style` + `analyzers`, com relatório `format-report.json`)
3. Testes com cobertura (`dotnet test --collect:"XPlat Code Coverage"`)
4. Build da imagem Docker
5. Teste end-to-end: `docker compose` (imagem buildada + PostgreSQL) + `scripts/smoke-test.sh` + screenshot automático com Playwright
6. Publicação das evidências (artifact `evidencias-pipeline`)

**CD** (tags semver `vX.Y.Z`):
1. **publish**: push da imagem para o GHCR (`ghcr.io/enzoblousa/boletim-escolar`) com as tags `X.Y.Z`, `X.Y` e `sha-…`
2. **deploy-homologacao**: deploy com docker compose no Environment `homologacao` + smoke test + rollback automático se falhar
3. **deploy-producao**: o mesmo no Environment `producao`, que exige **aprovação manual**
4. **release**: promove a imagem para `latest` e cria a GitHub Release (só para versões que passaram nos dois ambientes)

**Rollback manual**: workflow `Deploy` (`workflow_dispatch`), informando ambiente e versão.

## Segredos e configuração
Nenhuma senha fica no código. Localmente: `.env` (fora do git, modelo em `.env.example`). No pipeline: Secrets e Variables dos GitHub Environments `homologacao` e `producao`, mais o `GITHUB_TOKEN` efêmero para o registry. Detalhes: [`SEGREDOS.md`](Documentation/SEGREDOS.md).

## Versionamento e rollback
Versionamento semântico por tags git (`v1.0.0`, `v1.1.0`, …), propagado para a imagem, as labels OCI, o `GET /version` e as GitHub Releases. Simulação documentada de uma release com falha (`v1.1.0`), barrada em homologação com rollback automático, e de um rollback manual em produção: [`VERSIONAMENTO-E-ROLLBACK.md`](Documentation/VERSIONAMENTO-E-ROLLBACK.md).

## Tipos de testes implementados
- **Testes unitários** (`CalculadoraTests.cs`): cálculo da média, aprovação, reprovação, validação de notas inválidas.
- **Teste de regressão** (`CalculadoraTests.cs`): trava o valor exato da nota de corte (6.0) para a regra de aprovação.
- **Testes de integração/API** (`ApiIntegrationTests.cs`): fluxo completo via HTTP real (`WebApplicationFactory`), com cadastro, registro de notas e consulta de média e situação, além de `/health` e `/version`.
- **Smoke test** (`scripts/smoke-test.sh`): roda contra a imagem real com PostgreSQL, no CI e em cada deploy. É ele que decide o rollback.

## Evidências
- Execuções da pipeline: https://github.com/enzoblousa/boletim-escolar/actions
- Imagens publicadas: https://github.com/enzoblousa/boletim-escolar/pkgs/container/boletim-escolar
- Releases: https://github.com/enzoblousa/boletim-escolar/releases
- Histórico de deploys por ambiente: https://github.com/enzoblousa/boletim-escolar/deployments
- Relatório do linter, `.trx`, cobertura e `screenshot-execucao.png`: artifact `evidencias-pipeline` de cada execução
- Simulação de falha e rollback, com links das runs: [`VERSIONAMENTO-E-ROLLBACK.md`](Documentation/VERSIONAMENTO-E-ROLLBACK.md)

## Conclusão
O Docker e o Docker Compose garantem que a aplicação e suas dependências rodam da mesma forma em qualquer máquina, no CI e nos ambientes de deploy. A esteira automatiza build, análise estática, testes e entrega: cada tag semver vira uma imagem versionada no registry, que passa por homologação e produção com smoke test. Se algo falha, o rollback automático volta para a última versão estável, como mostra a simulação da `v1.1.0`. Os segredos ficam fora do código, nos Environments do GitHub.
