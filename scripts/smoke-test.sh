#!/usr/bin/env bash
# Smoke test da API publicada: espera o /health, confere a versão no ar e exercita o fluxo cadastro -> notas -> consulta.
# Uso: scripts/smoke-test.sh [BASE_URL] [VERSAO_ESPERADA]
# Sai com código != 0 se qualquer verificação falhar (é isso que dispara o rollback no scripts/deploy.sh).
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
VERSAO_ESPERADA="${2:-}"
TIMEOUT_SEGUNDOS="${SMOKE_TIMEOUT:-60}"

echo "[smoke] aguardando ${BASE_URL}/health (até ${TIMEOUT_SEGUNDOS}s)..."
for i in $(seq 1 "$TIMEOUT_SEGUNDOS"); do
  if [ "$(curl -s "${BASE_URL}/health" || true)" = "Healthy" ]; then
    echo "[smoke] /health = Healthy"
    break
  fi
  if [ "$i" -eq "$TIMEOUT_SEGUNDOS" ]; then
    echo "[smoke] FALHA: /health não ficou Healthy a tempo"
    exit 1
  fi
  sleep 1
done

VERSAO_NO_AR=$(curl -sf "${BASE_URL}/version" | jq -r '.versao')
echo "[smoke] versão no ar: ${VERSAO_NO_AR}"
if [ -n "$VERSAO_ESPERADA" ] && [ "$VERSAO_NO_AR" != "$VERSAO_ESPERADA" ]; then
  echo "[smoke] FALHA: esperado ${VERSAO_ESPERADA}, mas está no ar ${VERSAO_NO_AR}"
  exit 1
fi

ALUNO_ID=$(curl -sf -X POST "${BASE_URL}/alunos" \
  -H "Content-Type: application/json" -d '{"nome":"Smoke Test"}' | jq -r '.id') \
  || { echo "[smoke] FALHA: POST /alunos"; exit 1; }

curl -sf -X POST "${BASE_URL}/alunos/${ALUNO_ID}/notas" \
  -H "Content-Type: application/json" -d '{"nota1":8.0,"nota2":6.0}' > /dev/null \
  || { echo "[smoke] FALHA: POST /alunos/${ALUNO_ID}/notas"; exit 1; }

RESULTADO=$(curl -sf "${BASE_URL}/alunos/${ALUNO_ID}") \
  || { echo "[smoke] FALHA: GET /alunos/${ALUNO_ID}"; exit 1; }
if [ "$(echo "$RESULTADO" | jq -r '"\(.media)|\(.situacao)"')" != "7|Aprovado" ]; then
  echo "[smoke] FALHA: resposta inesperada: ${RESULTADO}"
  exit 1
fi

echo "[smoke] OK: fluxo cadastro -> notas -> consulta funcionando (${RESULTADO})"
