#!/usr/bin/env bash
# =========================================================
# Atalho para o deploy atual via JAR.
# A lógica real está em ./infra/deploy-jar.sh.
# =========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[deploy] Iniciando deploy via JAR + AWS CLI..."
"${SCRIPT_DIR}/infra/deploy-jar.sh"
echo "[deploy] Concluído."
