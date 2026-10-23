# Extensões do VS Code — quais instalar e por quê

Lista do que é necessário (ou fortemente recomendado) para trabalhar neste repositório no VS Code, e a razão de cada uma — ligada a uma parte específica do projeto, não genérica.

## Necessárias

- **C# Dev Kit** (`ms-dotnettools.csdevkit`) e **C#** (`ms-dotnettools.csharp`) — dão IntelliSense, build, debug e um Test Explorer integrado para os dois projetos da solução (`src/MediaEscolar.Api` e `tests/MediaEscolar.Tests`). Sem elas o VS Code trata `.cs` como texto puro, sem autocomplete, navegação ou rodar/depurar testes pelo editor.

- **Docker** (`ms-azuretools.vscode-docker`) — syntax highlighting e validação do `Dockerfile` da raiz (ver `DOCKERFILE.md`), além de uma interface para buildar/rodar/inspecionar a imagem `media-escolar` e seus containers sem digitar `docker build`/`docker run` manualmente toda vez.

- **GitHub Actions** (`github.vscode-github-actions`) — valida a sintaxe do `.github/workflows/ci-cd.yml` e `deploy.yml` (ver `CI-CD.md`) direto no editor, com autocomplete dos campos do workflow, e permite ver o status/log das runs sem abrir o navegador.

- **Coverage Gutters** (`ryanluker.vscode-coverage-gutters`) — lê o `coverage.cobertura.xml` gerado por `dotnet test --collect:"XPlat Code Coverage"` (ver `RESULTADOS-TESTES.md`) e pinta, linha a linha, o que está coberto ou não direto no editor — evita ter que abrir `coveragereport/index.html` no navegador só para checar uma classe.

## Recomendadas

- **TRX Test Report** — abre o `test-results.trx` (formato VSTest, gerado pelo `dotnet test`) como relatório legível dentro do VS Code, em vez de ler o XML cru ou precisar do Visual Studio completo.

- **YAML** (`redhat.vscode-yaml`) — validação de schema genérica para arquivos `.yml`; complementa a extensão de GitHub Actions, útil se o repositório ganhar outros arquivos YAML além dos workflows — como o `docker-compose.yml`.

## Opcional

- **REST Client** (`humao.rest-client`) ou **Thunder Client** (`rangav.vscode-thunder-client`) — testar os endpoints da API (`POST /alunos`, `POST /alunos/{id}/notas`, `GET /alunos/{id}`, `GET /alunos`) direto do editor, sem precisar montar comandos `curl` manualmente como faz o `scripts/smoke-test.sh`.
