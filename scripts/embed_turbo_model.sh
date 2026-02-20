#!/bin/bash
set -euo pipefail

MODEL_ID="${SPEEX_BUNDLED_MODEL_ID:-openai_whisper-large-v3-v20240930_turbo}"
SOURCE_ROOT_DEFAULT="$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml"
SOURCE_ROOT="${SPEEX_MODEL_SOURCE_ROOT:-$SOURCE_ROOT_DEFAULT}"
SOURCE_MODEL_DIR="$SOURCE_ROOT/$MODEL_ID"

DEST_ROOT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Models/whisperkit-coreml"
DEST_MODEL_DIR="$DEST_ROOT/$MODEL_ID"

if [[ "${SPEEX_SKIP_EMBED_MODEL:-0}" == "1" ]]; then
  echo "[Speex] Skipping embedded model copy (SPEEX_SKIP_EMBED_MODEL=1)"
  exit 0
fi

if [[ -d "$DEST_MODEL_DIR" ]] && [[ -n "$(ls -A "$DEST_MODEL_DIR" 2>/dev/null || true)" ]]; then
  echo "[Speex] Bundled model already present in app resources: $MODEL_ID"
  exit 0
fi

if [[ ! -d "$SOURCE_MODEL_DIR" ]] || [[ -z "$(ls -A "$SOURCE_MODEL_DIR" 2>/dev/null || true)" ]]; then
  echo "[Speex] ⚠️ Missing local model cache: $SOURCE_MODEL_DIR"
  echo "[Speex]    Open Speex once and let it download the turbo model, then rebuild."

  if [[ "$CONFIGURATION" == "Release" ]] || [[ "${SPEEX_REQUIRE_EMBEDDED_MODEL:-0}" == "1" ]]; then
    echo "[Speex] ❌ Release build requires bundled model files."
    exit 1
  fi

  exit 0
fi

mkdir -p "$DEST_ROOT"
rsync -a --delete "$SOURCE_MODEL_DIR/" "$DEST_MODEL_DIR/"

echo "[Speex] ✅ Embedded turbo model into app bundle: $MODEL_ID"
