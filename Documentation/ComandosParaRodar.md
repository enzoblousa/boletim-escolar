# Setup e Run do Back-End e da Infra (docker compose)
---
1) abrir o projeto no vscode
2) abrir docker desktop

extensões úteis:
- ThunderClient = conseguir fazer as requests e ver as responses da api
- Trx viewer = permite visualizar arquivos .trx
- Coverage Gutters = faz um display de cobertura gerado por xml
- Live Server(opcional)
- C# Dev Kit(opcional)

3)
```bash
dotnet --version #checar se sdk do dotnet 8 está instalado localmente na máquina
```
4)
```bash
docker --version          #verificar se docker cli está instalado localmente na máquina
docker compose version    #verificar se o docker compose está instalado
```

5)
```bash
cp .env.example .env #cria o arquivo de configuração local (NÃO vai pro git), preencha o POSTGRES_PASSWORD
```
6)
```bash
docker compose up -d --build #constrói a imagem (dockerfile) e sobe a API + PostgreSQL
docker compose ps            #api e db devem aparecer como "healthy"
```
7)
```bash
./scripts/smoke-test.sh #verifica health, versão e o fluxo completo da API
```
8)
```bash
docker compose down     #para tudo (os dados continuam no volume)
docker compose down -v  #para tudo e apaga os dados do banco
```

testar metodos (base: http://localhost:8080):
```bash
[GET] http://localhost:8080/health
    Response: Healthy
    #verifica se a API está no ar e conectada ao banco
```
```bash
[GET] http://localhost:8080/version
    Response:
    { "versao": "1.0.0" }
    #versão semântica da imagem que está rodando
```
```bash
[POST] http://localhost:8080/alunos #CadastrarAlunoRequest
    body:
    {
        "nome": "Enzo"
    }
    Response (201 Created):
    {
        "id": 1,
        "nome": "Enzo",
        "nota1": null,
        "nota2": null
    }
    #cadastra um aluno, o id é gerado pelo banco
```
```bash
[GET] http://localhost:8080/alunos
    Response:
    [{
        "id": 1,
        "nome": "Enzo",
        "nota1": null,
        "nota2": null
    }]
    #retorna listagem de alunos
```
```bash
[POST] http://localhost:8080/alunos/1/notas #RegistrarNotasRequest
    body:
    {
        "nota1": 5.5,
        "nota2": 8.0
    }
    #notas devem estar entre 0 e 10, senão retorna 400
```
```bash
[GET] http://localhost:8080/alunos/1 #pesquisa por ID
    Response:
    {
        "id": 1,
        "nome": "Enzo",
        "nota1": 5.5,
        "nota2": 8.0,
        "media": 6.75,
        "situacao": "Aprovado"
    }
```

# Deploy e rollback (local)
---
```bash
APP_VERSION=1.0.0 docker compose up -d --no-build #sobe uma versão já publicada no GHCR
./scripts/deploy.sh 1.1.0        #deploy da 1.1.0 com rollback automático pra versão que estava no ar se o smoke test falhar
./scripts/deploy.sh 1.0.0        #rollback manual: reimplanta uma versão específica
```

# Testes
---
```bash
#na root do projeto
dotnet test #executa todas as suites de teste (Unitários, regressão e API)
```
```bash
dotnet test --filter "FullyQualifiedName=namespace.testClass.methodName"
#testes unitários locais específicos
```
```bash
dotnet test --logger "trx;LogFileName=test-results.trx" --collect:"XPlat Code Coverage" --results-directory ./TestResults
#realiza todos os testes, registra em arquivos de evidência .trx no diretório TestResults
```
```bash
reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"coveragereport" -reporttypes:Html
```
