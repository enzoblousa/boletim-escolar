# Gestão de configurações e segredos

**Nenhuma senha ou credencial fica no código-fonte.** Toda configuração sensível vem de variável de ambiente, e quem preenche essas variáveis depende de onde a aplicação roda.

## De onde vem cada valor

| Valor | Sensível? | Local (`docker compose`) | Pipeline (GitHub Actions) |
|---|---|---|---|
| `POSTGRES_PASSWORD` | **Sim** | `.env` (fora do git) | **Secret** do Environment (`homologacao` / `producao`, senhas diferentes) |
| `POSTGRES_USER`, `POSTGRES_DB` | Não | `.env` | **Variable** do Environment |
| `ASPNETCORE_ENVIRONMENT` | Não | `.env` | **Variable** do Environment (`Staging` / `Production`) |
| Login no GHCR | **Sim** | `docker login ghcr.io` (token pessoal, só se precisar baixar a imagem) | `GITHUB_TOKEN` efêmero, gerado pelo Actions a cada run |
| Senha do banco de CI | Sim (descartável) | — | Gerada na hora com `openssl rand -hex 16` |

## Como a API recebe a connection string

`Program.cs` lê `builder.Configuration.GetConnectionString("Default")`. No container, essa configuração vem da variável de ambiente `ConnectionStrings__Default`, que o `docker-compose.yml` monta a partir de `POSTGRES_*`:

```yaml
ConnectionStrings__Default: Host=db;Port=5432;Database=${POSTGRES_DB:-media_escolar};Username=${POSTGRES_USER:-media_escolar};Password=${POSTGRES_PASSWORD:?defina POSTGRES_PASSWORD no .env}
```

O `:?` faz o compose **recusar subir** se a senha não foi definida, em vez de cair numa senha padrão.

`appsettings.json` e `appsettings.Development.json` não contêm connection string nem senha.

## Local

```bash
cp .env.example .env      # .env está no .gitignore e no .dockerignore
# edite .env e preencha POSTGRES_PASSWORD
docker compose up -d --build
```

`.env.example` (versionado) lista só os **nomes** das variáveis, sem valores sensíveis.

## Pipeline

Os segredos ficam em **Settings → Environments → `<ambiente>` → Environment secrets**, e as configurações não sensíveis em **Environment variables**. O `deploy.yml` injeta os dois como variáveis de ambiente do job:

```yaml
environment: ${{ inputs.ambiente }}
env:
  POSTGRES_PASSWORD: ${{ secrets.POSTGRES_PASSWORD }}
  POSTGRES_USER: ${{ vars.POSTGRES_USER }}
  POSTGRES_DB: ${{ vars.POSTGRES_DB }}
  ASPNETCORE_ENVIRONMENT: ${{ vars.ASPNETCORE_ENVIRONMENT }}
```

- Como o deploy é um *reusable workflow*, os jobs chamadores em `ci-cd.yml` usam `secrets: inherit`. Sem isso, os Environment secrets chegam vazios ao `deploy.yml`. Foi o que aconteceu na primeira execução da `v1.0.0`: o passo de validação barrou o deploy antes de subir qualquer coisa.
- O GitHub mascara (`***`) qualquer valor de secret que apareça nos logs.
- Secrets de Environment só ficam disponíveis para jobs que declaram aquele `environment`, e o Environment `producao` ainda exige aprovação manual antes de o job rodar.
- O passo "Validar configuração do ambiente" falha cedo, com mensagem clara, se o secret não existir.
- O `GITHUB_TOKEN` tem permissões mínimas por job (`contents: read` por padrão; `packages: write` só no `publish`; `packages: read` no deploy; `contents: write` só no `release`).

## Como (re)criar os segredos

Pela interface: *Settings → Environments → homologacao/producao → Add secret*. Pela CLI:

```bash
openssl rand -hex 24 | gh secret set POSTGRES_PASSWORD --env homologacao
openssl rand -hex 24 | gh secret set POSTGRES_PASSWORD --env producao
gh variable set POSTGRES_DB --env producao --body media_escolar
gh secret list --env producao   # lista nomes e datas, nunca os valores
```
