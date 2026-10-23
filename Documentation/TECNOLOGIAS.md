# Tecnologias utilizadas — o quê, para quê e onde

Lista de toda tecnologia/ferramenta usada no repositório, com o motivo de cada uma e o ponto exato do código/configuração onde ela aparece.

## Linguagem e runtime

- **C# / .NET 8** — linguagem e runtime de toda a aplicação e dos testes.
  Onde: `src/MediaEscolar.Api/**/*.cs`, `tests/MediaEscolar.Tests/**/*.cs`; versão do SDK fixada em `global.json` (`"version": "8.0.416"`, `rollForward: latestFeature`); `TargetFramework` declarado em `src/MediaEscolar.Api/MediaEscolar.Api.csproj` e `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`.

- **Nullable reference types** e **ImplicitUsings** — recursos do compilador C# para reduzir `NullReferenceException` e boilerplate de `using`.
  Onde: `<Nullable>enable</Nullable>` e `<ImplicitUsings>enable</ImplicitUsings>` em ambos os `.csproj` (`src/MediaEscolar.Api/MediaEscolar.Api.csproj`, `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`).

## Framework web

- **ASP.NET Core Minimal API** — framework HTTP usado para expor os endpoints da API sem Controllers, direto no `Program.cs`.
  Onde: `<Project Sdk="Microsoft.NET.Sdk.Web">` em `src/MediaEscolar.Api/MediaEscolar.Api.csproj`; rotas `MapPost`/`MapGet` em `src/MediaEscolar.Api/Program.cs` (endpoints `/alunos`, `/alunos/{id}/notas`, `/alunos/{id}`, `/health`, `/version`).

- **Health Checks do ASP.NET Core** (+ `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore`) — endpoint `/health` que testa a conexão com o banco; usado pelo `HEALTHCHECK` do Dockerfile, pelo compose e pelo smoke test do deploy (que decide o rollback).
  Onde: `AddHealthChecks().AddDbContextCheck<AppDbContext>()` e `MapHealthChecks("/health")` em `src/MediaEscolar.Api/Program.cs`.

## Persistência

- **PostgreSQL 16** (`postgres:16-alpine`) — banco de dados da aplicação.
  Onde: serviço `db` em `docker-compose.yml` (ver `DOCKER-COMPOSE.md`).

- **Entity Framework Core 8** + **Npgsql** (`Npgsql.EntityFrameworkCore.PostgreSQL`) — ORM e provider do PostgreSQL; a connection string vem da variável de ambiente `ConnectionStrings__Default`.
  Onde: `src/MediaEscolar.Api/Data/AppDbContext.cs`; registro em `src/MediaEscolar.Api/Program.cs`; pacote em `src/MediaEscolar.Api/MediaEscolar.Api.csproj`.

- **EF Core InMemory** (`Microsoft.EntityFrameworkCore.InMemory`) — substitui o PostgreSQL nos testes de integração.
  Onde: `tests/MediaEscolar.Tests/ApiFactory.cs`; pacote em `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`.

- **`WebApplicationFactory`** (parte do ASP.NET Core) — permite instanciar a API inteira em memória para testar via HTTP real, sem precisar subir um servidor de fato.
  Onde: `tests/MediaEscolar.Tests/ApiFactory.cs` e `tests/MediaEscolar.Tests/ApiIntegrationTests.cs`; exposto pelo `public partial class Program;` no final de `src/MediaEscolar.Api/Program.cs` (necessário para o `WebApplicationFactory<Program>` enxergar o entry point top-level).

## Testes

- **xUnit** — framework de testes unitários e de integração.
  Onde: pacotes `xunit` e `xunit.runner.visualstudio` em `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`; testes em `tests/MediaEscolar.Tests/CalculadoraTests.cs` e `tests/MediaEscolar.Tests/ApiIntegrationTests.cs`.

- **Microsoft.AspNetCore.Mvc.Testing** — fornece o `WebApplicationFactory` usado nos testes de integração (sobe a API real em memória e bate via `HttpClient`).
  Onde: pacote em `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`; uso em `tests/MediaEscolar.Tests/ApiIntegrationTests.cs`.

- **Microsoft.NET.Test.Sdk** — runner/infraestrutura necessária para o `dotnet test` descobrir e executar os testes do projeto.
  Onde: pacote em `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`.

- **coverlet.collector** — coletor de cobertura de código, plugado no `dotnet test` via `--collect:"XPlat Code Coverage"`.
  Onde: pacote em `tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj`; acionado no step "Executar testes com cobertura" de `.github/workflows/ci-cd.yml`; saída em `TestResults/<guid>/coverage.cobertura.xml` (ver `RESULTADOS-TESTES.md`).

- **InternalsVisibleTo** — atributo do MSBuild que expõe os tipos `internal` da API para o projeto de testes.
  Onde: `<InternalsVisibleTo Include="MediaEscolar.Tests" />` em `src/MediaEscolar.Api/MediaEscolar.Api.csproj`.

## Qualidade de código

- **`dotnet format`** (style + analyzers, built-in do SDK do .NET) — linter/formatter estático que falha a pipeline se o código não seguir as convenções, sem aplicar correção automática (`--verify-no-changes`).
  Onde: step "Analise estatica (dotnet format)" em `.github/workflows/ci-cd.yml`, rodado contra `MediaEscolar.sln`; relatórios em `TestResults/format-style/` e `TestResults/format-analyzers/` (ver `CI-CD.md`).

## Containerização

- **Docker** (multi-stage build otimizado) — empacota a API em uma imagem reproduzível: cache de restore, runtime Alpine, usuário não-root, `HEALTHCHECK` e versão/labels OCI.
  Onde: `Dockerfile` na raiz (`FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build` e `FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS final`); detalhado em `DOCKERFILE.md`.

- **`.dockerignore`** — evita copiar arquivos irrelevantes ou sensíveis (`bin/`, `obj/`, `.git`, `.env`, docs) para o contexto de build da imagem.
  Onde: `.dockerignore` na raiz.

- **Docker Compose** — orquestração local da API + PostgreSQL (healthchecks, `depends_on`, volume); também usado no teste end-to-end do CI e no deploy simulado.
  Onde: `docker-compose.yml` e `.env.example` na raiz; detalhado em `DOCKER-COMPOSE.md`.

- **GitHub Container Registry (GHCR)** — registry onde as imagens versionadas são publicadas (`ghcr.io/enzoblousa/boletim-escolar:<versão>`).
  Onde: job `publish` em `.github/workflows/ci-cd.yml`.

## CI/CD

- **GitHub Actions** — orquestra a pipeline de build, lint, testes e publicação de evidências a cada push/PR para `main`.
  Onde: `.github/workflows/ci-cd.yml`; detalhado passo a passo em `CI.md`.
  - `actions/checkout@v7` — clona o repositório na VM do runner.
  - `actions/setup-dotnet@v6` — instala o SDK do .NET 8 na VM (`dotnet-version: '8.0.x'`).
  - `actions/upload-artifact@v7` — publica a pasta `TestResults/` (relatórios de lint, `.trx`, cobertura, screenshot) como artifact `evidencias-pipeline`.
  - `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/metadata-action@v6`, `docker/build-push-action@v7` — login no GHCR com `GITHUB_TOKEN`, geração das tags semver (`1.2.3`, `1.2`, `sha-…`; `latest` só após produção) e build/push com cache.
  - **Reusable workflow** (`.github/workflows/deploy.yml`) — deploy por ambiente, chamado pelo CI-CD e disparável manualmente (`workflow_dispatch`) para rollback manual.

- **GitHub Environments, Secrets e Variables** — ambientes `homologacao` e `producao` (este com aprovação manual), cada um com seus segredos (`POSTGRES_PASSWORD`) e configurações (`POSTGRES_DB`, `POSTGRES_USER`, `ASPNETCORE_ENVIRONMENT`).
  Onde: `environment:` em `.github/workflows/deploy.yml`; detalhado em `SEGREDOS.md`.

- **GitHub Releases + tags SemVer** — cada tag `vX.Y.Z` dispara o CD; a Release só é criada após deploy bem-sucedido em produção e serve de "última versão estável" para rollback.
  Onde: job `release` em `.github/workflows/ci-cd.yml`; detalhado em `VERSIONAMENTO-E-ROLLBACK.md`.

- **Scripts de deploy (bash)** — `scripts/deploy.sh` (deploy com rollback automático) e `scripts/smoke-test.sh` (health + versão + fluxo completo).
  Onde: pasta `scripts/`, usados pelos workflows e localmente.

- **Playwright** (`npx playwright@1.48.0`, Chromium headless) — tira um screenshot automático do endpoint final da API, como evidência visual de que o fluxo completo funciona dentro do container real.
  Onde: step "Capturar screenshot da execução" em `.github/workflows/ci-cd.yml`; gera `TestResults/screenshot-execucao.png`.

- **`curl`** e **`jq`** — esperam a API responder, exercitam os endpoints e validam o JSON de resposta (id, média, situação, versão).
  Onde: `scripts/smoke-test.sh` e `scripts/deploy.sh`.

## Build/dependências

- **MSBuild** (via `dotnet`) e **NuGet** — sistema de build e gerenciador de pacotes do .NET, responsável por restaurar (`dotnet restore`), compilar (`dotnet build`/`dotnet publish`) e referenciar todos os pacotes citados acima.
  Onde: `MediaEscolar.sln` na raiz (agrega os dois projetos); `<PackageReference>` nos `.csproj` de `src/MediaEscolar.Api` e `tests/MediaEscolar.Tests`.

## Controle de versão

- **Git / GitHub** — versionamento do código e hospedagem do repositório; também é o que dispara a pipeline de CI (push/PR) e hospeda os artifacts gerados por ela.
  Onde: `.git/`, `.gitignore` na raiz; badge de status do CI no topo do `README.md`.

## Editor (não faz parte do runtime, mas do fluxo de desenvolvimento)

- **VS Code + extensões** (C# Dev Kit, Docker, GitHub Actions, Coverage Gutters, TRX Test Report, YAML) — ambiente de edição recomendado para este repositório, cada extensão ligada a uma parte específica do projeto (build/debug de C#, `Dockerfile`, `ci-cd.yml`/`deploy.yml`, `docker-compose.yml`, cobertura, `.trx`).
  Onde: detalhado em `EXTENSOES.md` (sem arquivo de configuração no repositório, é uma recomendação de ambiente).
