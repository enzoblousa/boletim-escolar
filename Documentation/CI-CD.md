# `.github/workflows/ci.yml` — explicação da pipeline

Pipeline de CI no GitHub Actions: builda a imagem Docker, checa formatação/estilo, roda os testes com cobertura, exercita a API real via Docker e publica tudo como evidência. Roda a cada push ou pull request para a branch `main`.

## Gatilho e job

```yaml
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
```

- **`on.push` / `on.pull_request`** — a pipeline dispara em dois eventos: push direto na `main` e qualquer PR que tenha `main` como destino. Isso garante que um PR já mostra o resultado da pipeline antes do merge.
- **`runs-on: ubuntu-latest`** — cada execução roda numa VM efêmera do GitHub com Ubuntu, criada do zero (sem nada instalado além do runner base — por isso os steps seguintes precisam instalar/restaurar tudo).

## Steps, em ordem

### 1. Checkout
```yaml
- name: Checkout
  uses: actions/checkout@v4
```
Clona o repositório (no commit/PR que disparou a run) para dentro da VM. Sem isso, nenhum step seguinte teria acesso ao código.

### 2. Setup .NET
```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'
```
Instala o SDK do .NET 8 na VM (a imagem `ubuntu-latest` não vem com .NET pré-instalado). `8.0.x` aceita qualquer patch da versão 8.0, sempre a mais recente disponível.

### 3. Build da imagem Docker
```yaml
- name: Build da imagem Docker
  run: docker build -t media-escolar .
```
Builda a imagem a partir do `Dockerfile` da raiz (ver `DOCKERFILE.md`), com a tag `media-escolar`. Essa imagem é reaproveitada depois, no step de screenshot — ou seja, a pipeline testa a imagem real que seria publicada, não só o código-fonte.

### 4. Restaurar dependências
```yaml
- name: Restaurar dependencias
  run: dotnet restore MediaEscolar.sln
```
Baixa os pacotes NuGet referenciados pela solução (API + testes). Precisa rodar antes de `dotnet format`/`dotnet test`, senão eles falham por falta de dependências resolvidas.

### 5. Análise estática (dotnet format)
```yaml
- name: Analise estatica (dotnet format)
  run: |
    dotnet format style MediaEscolar.sln --verify-no-changes --report ./TestResults/format-style
    dotnet format analyzers MediaEscolar.sln --verify-no-changes --report ./TestResults/format-analyzers
```
Roda o formatter/analisador estático do .NET em duas categorias: `style` (convenções de código) e `analyzers` (regras de analisadores Roslyn com correção automática). `--verify-no-changes` não corrige nada — só falha a pipeline (exit code ≠ 0) se houvesse algo a corrigir. `--report` grava um `format-report.json` por categoria, em pastas separadas dentro de `TestResults/`.

> A categoria `whitespace` (indentação, linha em branco, espaço sobrando) foi deliberadamente excluída desse gate: sem um `.editorconfig` no repositório, ela usa as convenções padrão do .NET e falha por detalhes triviais sem relação com a qualidade real do código.

### 6. Executar testes com cobertura
```yaml
- name: Executar testes com cobertura
  run: dotnet test MediaEscolar.sln --logger "trx;LogFileName=test-results.trx" --collect:"XPlat Code Coverage" --results-directory ./TestResults
```
Roda todos os testes (unitários, regressão e integração) via xUnit/VSTest, grava o resultado em `TestResults/test-results.trx` e coleta cobertura de código (via coverlet) em `TestResults/<guid>/coverage.cobertura.xml`. Se algum teste falhar, a pipeline falha aqui.

### 7. Capturar screenshot da execução
```yaml
- name: Capturar screenshot da execução
  run: |
    docker run -d --name media-escolar -p 8080:8080 media-escolar
    ...
    npx --yes playwright@1.48.0 screenshot "http://localhost:8080/alunos/${ALUNO_ID}" ./TestResults/screenshot-execucao.png
```
Sobe um container real a partir da imagem buildada no step 3, espera a API responder (loop de `curl` por até 30s), cadastra um aluno de teste, registra notas via `curl`, e usa o Playwright (Chromium headless) para fotografar o JSON retornado pela API ao consultar aquele aluno — gerando `screenshot-execucao.png`. É evidência de que a API funciona de ponta a ponta dentro da imagem Docker real, não só que os testes unitários passam isoladamente.

### 8. Encerrar container da aplicação
```yaml
- name: Encerrar container da aplicacao
  if: always()
  run: docker rm -f media-escolar || true
```
Remove o container iniciado no step anterior. `if: always()` garante que isso roda mesmo se um step anterior falhar (evita deixar containers "pendurados" na VM, embora ela seja efêmera e descartada no fim da run de qualquer forma — é mais boa prática que necessidade real aqui).

### 9. Publicar evidências
```yaml
- name: Publicar evidencias (relatorio do linter, resultados de teste, cobertura e screenshot)
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: evidencias-pipeline
    path: ./TestResults
```
Empacota toda a pasta `TestResults/` (relatórios de format, `.trx`, cobertura e screenshot) e publica como artifact `evidencias-pipeline`, disponível para download na run no GitHub Actions por um tempo limitado (padrão de 90 dias). `if: always()` garante que o artifact é publicado mesmo se um step anterior falhar — útil justamente para investigar por que falhou (ex.: ver o `format-report.json` ou o `.trx` com os testes que quebraram).

## Onde quebra mais fácil

- **Step 5** (`dotnet format`) — quebra se o código tiver problemas de estilo/analisadores; ver `RESULTADOS-TESTES.md` para detalhes de como reproduzir localmente.
- **Step 6** (`dotnet test`) — quebra se algum teste falhar.
- **Step 7** (screenshot) — quebra se a API não subir a tempo no container, ou se o fluxo cadastro → notas → consulta retornar algo inesperado.
