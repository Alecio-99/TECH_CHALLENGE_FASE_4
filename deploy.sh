#!/usr/bin/env bash
# =========================================================
# Atalho para o deploy completo (build + infra na AWS).
# A lógica real está em ./infra/deploy-infra.sh.
# =========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[deploy] Iniciando deploy via Docker + AWS CLI..."
"${SCRIPT_DIR}/infra/deploy-infra.sh"
echo "[deploy] Concluído."
