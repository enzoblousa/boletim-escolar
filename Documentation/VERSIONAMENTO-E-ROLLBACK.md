# Versionamento semântico e rollback

## Versionamento semântico (SemVer)

As versões seguem `MAJOR.MINOR.PATCH`:

- **PATCH** (`1.0.0 → 1.0.1`): correção sem mudança de comportamento da API.
- **MINOR** (`1.0.1 → 1.1.0`): funcionalidade nova, compatível com a anterior.
- **MAJOR** (`1.x → 2.0.0`): mudança incompatível (ex.: contrato da API).

A **tag git `vX.Y.Z` é a fonte da verdade**. Um único `git push origin vX.Y.Z` propaga a versão para todos os lugares:

| Onde | Como a versão aparece |
|---|---|
| Imagem no GHCR | `ghcr.io/enzoblousa/boletim-escolar:X.Y.Z`, `:X.Y`, `:sha-<commit>` (`docker/metadata-action`); `:latest` só depois de passar em produção (job `release`) |
| Labels OCI da imagem | `org.opencontainers.image.version=X.Y.Z`, `...revision=<commit>` |
| Assembly da API | `dotnet publish -p:Version=X.Y.Z` (padrão `<Version>` do `.csproj`) |
| API em execução | `GET /version` → `{"versao":"X.Y.Z"}`, verificado pelo smoke test |
| GitHub Release | criada **só** se a versão passou em homologação **e** produção |
| GitHub Deployments | histórico de qual ref foi implantada em cada Environment |

```bash
git tag -a v1.2.0 -m "v1.2.0: descrição"
git push origin v1.2.0      # dispara CI -> publish -> homologação -> (aprovação) produção -> release
```

## Como o rollback funciona

### Automático (`scripts/deploy.sh`)

1. Lê a versão que está no ar (`GET /version`).
2. Sobe a nova versão com `docker compose` (banco e volume continuam os mesmos).
3. Roda `scripts/smoke-test.sh`, que verifica `/health`, se `/version` bate com a versão esperada e o fluxo cadastro → notas → consulta.
4. **Se falhar**: imprime os logs da API, sobe de novo a versão anterior e roda o smoke test nela.
5. O job termina **com erro** mesmo que o rollback dê certo. Isso impede a promoção para o próximo ambiente e a criação da Release.

Como o ambiente de deploy é simulado num runner efêmero, o workflow primeiro **restaura o estado atual do ambiente**: sobe a última GitHub Release (última versão estável) e cria dados. A nova versão é implantada **por cima de um ambiente com banco e dados já existentes**, igual a um servidor real.

### Manual (`workflow_dispatch`)

Para voltar a qualquer versão publicada:

```bash
gh workflow run deploy.yml -f ambiente=producao -f versao=1.0.0
```

Ou pela interface: *Actions → Deploy → Run workflow*. Em produção, a execução também passa pela aprovação manual do Environment.

Localmente, o mesmo script funciona contra o `docker compose` da máquina: `./scripts/deploy.sh 1.0.0`.

---

## Simulação documentada (23/10/2026)

### Linha do tempo

| # | Versão | Evento | Resultado | Execução |
|---|---|---|---|---|
| 1 | `v1.0.0` | Primeira release com CD | Imagem publicada; deploy **barrado** pela validação de configuração (secret vazio no workflow reutilizável). Nada subiu. | [run 39963183740](https://github.com/enzoblousa/boletim-escolar/actions/runs/39963183740) |
| 2 | `v1.0.1` | Correção do pipeline (`secrets: inherit`) | ✅ homologação → aprovação → ✅ produção → Release `v1.0.1` | [run 39964205758](https://github.com/enzoblousa/boletim-escolar/actions/runs/39964205758) · [release](https://github.com/enzoblousa/boletim-escolar/releases/tag/v1.0.1) |
| 3 | `v1.1.0` | **Release defeituosa proposital** ([PR #3](https://github.com/enzoblousa/boletim-escolar/pull/3)) | ❌ smoke test falhou em homologação → ⏪ **rollback automático para 1.0.1** → produção não foi tocada, sem Release | [run 39965267691](https://github.com/enzoblousa/boletim-escolar/actions/runs/39965267691) · [job](https://github.com/enzoblousa/boletim-escolar/actions/runs/39965267691/job/120455130457) |
| 4 | — | Revert do defeito na `main` ([PR #4](https://github.com/enzoblousa/boletim-escolar/pull/4)) | ✅ CI | — |
| 5 | `1.0.0` | **Rollback manual** da produção (`1.0.1 → 1.0.0`) via `workflow_dispatch`, com aprovação | ✅ produção na 1.0.0 | [run 39966010445](https://github.com/enzoblousa/boletim-escolar/actions/runs/39966010445) |

### O defeito da `v1.1.0`

O PR #3 adicionou a propriedade `Email` ao `Aluno` **sem migration**:

- **Testes de integração** (EF Core InMemory): passam, porque o banco em memória é criado do zero com o modelo novo.
- **E2E do CI** (PostgreSQL novo, vazio): passa, porque o `EnsureCreated()` cria a tabela já com a coluna.
- **Homologação** (PostgreSQL que já tinha a tabela `alunos` da 1.0.1): o `EnsureCreated()` **não altera tabelas existentes**, então a coluna `Email` não existe e o `POST /alunos` retorna 500.

É um tipo de falha que só aparece em um ambiente com estado, e é exatamente o que o deploy sobre a última release estável procura detectar.

### Log do deploy em homologação (`v1.1.0`)

```
Ambiente atualmente na versão 1.0.1
[smoke] versão no ar: 1.0.1
[smoke] OK: fluxo cadastro -> notas -> consulta funcionando ({"id":1,...,"media":7,"situacao":"Aprovado"})
[deploy] versão atual no ar: 1.0.1
[deploy] subindo versão 1.1.0...
[smoke] /health = Healthy
[smoke] versão no ar: 1.1.0
[smoke] FALHA: POST /alunos
[deploy] smoke test da versão 1.1.0 FALHOU. Logs da API:
api-1  |  ---> Npgsql.PostgresException (0x80004005): 42703: column "Email" of relation "alunos" does not exist
[deploy] iniciando ROLLBACK para a versão 1.0.1...
[deploy] subindo versão 1.0.1...
[smoke] versão no ar: 1.0.1
[smoke] OK: fluxo cadastro -> notas -> consulta funcionando ({"id":2,...,"media":7,"situacao":"Aprovado"})
⏪ Deploy da versão **1.1.0** falhou no smoke test; **rollback automático para 1.0.1 concluído** e ambiente saudável.
{"versao":"1.0.1"}
```

O aluno `id 1`, criado antes do deploy, continuou no banco depois do rollback (o próximo recebeu `id 2`). O rollback troca só a imagem da API; os dados ficam preservados no volume.

Resultado no pipeline: `deploy-homologacao` ❌, `deploy-producao` e `release` **skipped**. A versão defeituosa nunca chegou a produção e não virou Release.

### Log do rollback manual em produção (`1.0.1 → 1.0.0`)

```
Ambiente atualmente na versão 1.0.1
[deploy] versão atual no ar: 1.0.1
[deploy] subindo versão 1.0.0...
[smoke] versão no ar: 1.0.0
✅ Deploy da versão **1.0.0** concluído (anterior: 1.0.1).
{"versao":"1.0.0"}
```

### Lições / próximos passos

- Mudanças de schema devem usar **migrations do EF Core** (`dotnet ef migrations add` + `Database.Migrate()`) em vez de `EnsureCreated()`.
- O smoke test em um ambiente com estado (homologação) pegou o que os testes automatizados não pegavam. Por isso homologação vem antes de produção.
