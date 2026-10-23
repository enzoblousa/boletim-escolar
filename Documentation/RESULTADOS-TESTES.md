# Resultados de testes — pastas e como usá-las

Este projeto produz resultados de teste em três lugares diferentes, cada um com uma finalidade e tecnologia própria. Este documento explica o que é cada um, como gerá-los/visualizá-los e onde encontrá-los.

## Visão geral

| Pasta / artifact | Onde fica | Comitado no git? | Gerado por |
|---|---|---|---|
| `TestResults/` | Local (sua máquina) e dentro do job do CI | Não (`.gitignore`) | `dotnet test` |
| `coveragereport/` | Raiz do repositório (local) | Não (gerado sob demanda) | `reportgenerator` (manual) |
| Artifact `evidencias-pipeline` | GitHub Actions (por execução) | Não (artifact, não arquivo) | Pipeline CI/CD |

## `TestResults/`

Pasta criada automaticamente quando você roda os testes localmente, e também recriada do zero a cada execução da pipeline (está no `.gitignore`, então nunca é comitada).

**Tecnologia:** [xUnit](https://xunit.net/) como framework de teste, executado pelo runner do VSTest (vem com o SDK do .NET), com [coverlet.collector](https://github.com/coverlet-coverage/coverlet) coletando a cobertura de código.

**Como gerar (sempre a partir da raiz do repositório):**
```bash
dotnet test MediaEscolar.sln --logger "trx;LogFileName=test-results.trx" --collect:"XPlat Code Coverage" --results-directory ./TestResults
```

> ⚠️ **Atenção para não duplicar a pasta:** se você rodar `dotnet test` de dentro de `tests/MediaEscolar.Tests/` (em vez da raiz) ou sem o `--results-directory ./TestResults`, o .NET cria uma *segunda* pasta `TestResults/` ali dentro, com outro conjunto de GUIDs. Ela é só lixo local (também ignorada pelo git) e pode ser apagada com segurança — sempre rode o comando acima a partir da raiz do repositório para gerar uma única pasta `TestResults/` na raiz.

**O que aparece dentro:**
- `test-results.trx` — relatório dos testes (quantos passaram/falharam, tempo de execução, stack trace de falhas). Formato XML do Visual Studio Test Results.
- `<guid>/coverage.cobertura.xml` — relatório de cobertura em formato Cobertura (dados brutos, não é para ler diretamente).
- Na pipeline (CI), essa mesma pasta também recebe `format-style/format-report.json` e `format-analyzers/format-report.json` (relatório do linter, um para cada categoria) e `screenshot-execucao.png` (ver seções abaixo).

**Como visualizar:**
- `.trx`: abra com o Visual Studio (`Test > Test Explorer > Open test results`) ou com a extensão "TRX Test Report" do VS Code. Também é só um XML, pode ser lido em qualquer editor de texto se for só para conferir os nomes dos testes e o resultado.
- `coverage.cobertura.xml`: não é feito para leitura direta — use o `coveragereport/` (próxima seção) para visualizar a cobertura de forma legível.

## `coveragereport/`

Relatório de cobertura em HTML, navegável, gerado localmente a partir do `coverage.cobertura.xml` acima. Não é commitado: a evidência oficial de cobertura é o `coverage.cobertura.xml` publicado em cada execução no artifact `evidencias-pipeline` (ver abaixo), e o HTML pode ser regerado a qualquer momento com o comando abaixo.

**Tecnologia:** [ReportGenerator](https://github.com/danielpalme/ReportGenerator) (ferramenta `dotnet-reportgenerator-globaltool`).

> Os testes de integração (`ApiIntegrationTests.cs`) não precisam de PostgreSQL: o `ApiFactory.cs` troca o banco por EF Core InMemory. O teste contra o PostgreSQL real acontece no smoke test do pipeline (CI e deploy).

**Como gerar/atualizar (depois de já ter rodado `dotnet test` com `--collect:"XPlat Code Coverage"`):**
```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"coveragereport" -reporttypes:Html
```

**Como visualizar:** abra `coveragereport/index.html` diretamente no navegador (duplo clique no arquivo, ou `start coveragereport/index.html` no Windows). Ele mostra o percentual de cobertura por classe (`MediaEscolar.Api_Calculadora.html`, `MediaEscolar.Api_Program.html`, etc.) com as linhas cobertas/não cobertas destacadas.

## Artifact `evidencias-pipeline` (GitHub Actions)

A cada execução da pipeline (`.github/workflows/ci-cd.yml`, job `build-and-test`), o passo final publica um artifact chamado `evidencias-pipeline` com o conteúdo da pasta `TestResults/` daquela execução específica — ou seja, é a versão "oficial" e mais completa dos resultados, gerada sem intervenção manual.

**Conteúdo do artifact:**
- `format-style/format-report.json` e `format-analyzers/format-report.json` — relatórios da análise estática (`dotnet format style` e `dotnet format analyzers`, ambos com `--report`). A categoria `whitespace` foi removida do gate por ser excessivamente rígida sem um `.editorconfig` no repositório.
- `test-results.trx` — relatório de testes daquela execução.
- `coverage.cobertura.xml` — cobertura daquela execução.
- `screenshot-execucao.png` — print automático (via Playwright headless) do JSON retornado pela API real, depois do smoke test (`scripts/smoke-test.sh`) exercitar o fluxo cadastro → notas → consulta contra a imagem Docker buildada na própria pipeline, rodando com PostgreSQL via `docker compose`.

**Como acessar:**
- Pela interface: abra a run em https://github.com/enzoblousa/boletim-escolar/actions, role até "Artifacts" no final da página e baixe `evidencias-pipeline.zip`.
- Pelo `gh` CLI:
  ```bash
  gh run list --branch main --limit 5
  gh run download <run-id> --name evidencias-pipeline -D ./evidencias-pipeline-baixado
  ```
