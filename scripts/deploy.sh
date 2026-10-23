#!/usr/bin/env bash
# Deploy de uma versão publicada no GHCR com docker compose, com rollback automático.
#
# Uso: scripts/deploy.sh <VERSAO> [VERSAO_ROLLBACK]
#   VERSAO           versão semântica da imagem (tag do GHCR, sem o "v"), ex.: 1.2.0
#   VERSAO_ROLLBACK  versão para a qual voltar se o deploy falhar.
#                    Se omitida, usa a versão que estava no ar antes do deploy (lida de /version).
#
# Fluxo: descobre a versão atual -> sobe a nova -> smoke test -> se falhar, sobe a anterior -> smoke test.
# Códigos de saída: 0 = deploy ok | 1 = deploy falhou e rollback ok (ou não havia para onde voltar) | 2 = rollback também falhou
# Credenciais: lidas do .env / variáveis de ambiente (no pipeline vêm dos Secrets do Environment).
set -euo pipefail

VERSAO="${1:?uso: scripts/deploy.sh <VERSAO> [VERSAO_ROLLBACK]}"
VERSAO_ROLLBACK="${2:-}"
PROJETO="${COMPOSE_PROJECT_NAME:-media-escolar}"
BASE_URL="${BASE_URL:-http://localhost:${APP_PORT:-8080}}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

compose() { docker compose -f "$RAIZ/docker-compose.yml" -p "$PROJETO" "$@"; }

resumo() {
  echo "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$1" >> "$GITHUB_STEP_SUMMARY"; fi
}

# --pull missing: baixa a imagem do GHCR só se ela ainda não existir localmente
subir() {
  echo "[deploy] subindo versão $1..."
  APP_VERSION="$1" compose up -d --no-build --pull missing
}

if [ -z "$VERSAO_ROLLBACK" ]; then
  VERSAO_ROLLBACK=$(curl -sf "${BASE_URL}/version" | jq -r '.versao' 2>/dev/null || true)
fi
echo "[deploy] versão atual no ar: ${VERSAO_ROLLBACK:-nenhuma}"

if subir "$VERSAO" && "$RAIZ/scripts/smoke-test.sh" "$BASE_URL" "$VERSAO"; then
  resumo "✅ Deploy da versão **${VERSAO}** concluído (anterior: ${VERSAO_ROLLBACK:-nenhuma})."
  exit 0
fi

echo "[deploy] smoke test da versão ${VERSAO} FALHOU. Logs da API:"
compose logs --tail 50 api || true

if [ -z "$VERSAO_ROLLBACK" ] || [ "$VERSAO_ROLLBACK" = "$VERSAO" ]; then
  resumo "❌ Deploy da versão **${VERSAO}** falhou e não há versão anterior para rollback."
  exit 1
fi

echo "[deploy] iniciando ROLLBACK para a versão ${VERSAO_ROLLBACK}..."
if subir "$VERSAO_ROLLBACK" && "$RAIZ/scripts/smoke-test.sh" "$BASE_URL" "$VERSAO_ROLLBACK"; then
  resumo "⏪ Deploy da versão **${VERSAO}** falhou no smoke test; **rollback automático para ${VERSAO_ROLLBACK} concluído** e ambiente saudável."
  exit 1
fi

resumo "🚨 Deploy da versão **${VERSAO}** falhou e o rollback para ${VERSAO_ROLLBACK} TAMBÉM falhou. Intervenção manual necessária."
exit 2
