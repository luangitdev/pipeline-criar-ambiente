#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

TIPO_AMBIENTE=""
REPO_URL=""
REPO_BRANCH=""
APP_VERSION=""
OUTPUT_WAR=""
WORKSPACE=""
GIT_USERNAME=""
GIT_TOKEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tipo-ambiente)
            TIPO_AMBIENTE="$2"
            shift 2
            ;;
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --repo-branch)
            REPO_BRANCH="$2"
            shift 2
            ;;
        --app-version)
            APP_VERSION="$2"
            shift 2
            ;;
        --output-war)
            OUTPUT_WAR="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --git-username)
            GIT_USERNAME="$2"
            shift 2
            ;;
        --git-token)
            GIT_TOKEN="$2"
            shift 2
            ;;
        *)
            log_error "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$TIPO_AMBIENTE" || -z "$REPO_URL" || -z "$REPO_BRANCH" || -z "$APP_VERSION" || -z "$OUTPUT_WAR" || -z "$WORKSPACE" || -z "$GIT_USERNAME" || -z "$GIT_TOKEN" ]]; then
    log_error "Parâmetros obrigatórios faltando para build do artefato."
    exit 1
fi

BUILD_ROOT="${WORKSPACE}/temp/app_source"
REPO_DIR="${BUILD_ROOT}/repo"
mkdir -p "$BUILD_ROOT"
rm -rf "$REPO_DIR"

log "📥 Clonando aplicação (${TIPO_AMBIENTE})"
log "   - URL: $REPO_URL"
log "   - Branch: $REPO_BRANCH"
log "   - Versão desejada da app: $APP_VERSION"
AUTH_B64="$(printf '%s:%s' "$GIT_USERNAME" "$GIT_TOKEN" | base64 | tr -d '\n')"
git_with_auth() {
    git -c http.extraHeader="Authorization: Basic ${AUTH_B64}" "$@"
}

git_with_auth clone --no-checkout --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"

build_ok=false
pushd "$REPO_DIR" >/dev/null

resolved_ref=""
tag_ref=""
branch_ref=""

for candidate in "$APP_VERSION" "v$APP_VERSION"; do
    if git_with_auth ls-remote --exit-code --tags origin "refs/tags/${candidate}" >/dev/null 2>&1; then
        tag_ref="$candidate"
        break
    fi
done

if [[ -n "$tag_ref" ]]; then
    log "🔖 Usando tag da aplicação: $tag_ref"
    git_with_auth fetch --depth 1 origin "refs/tags/${tag_ref}:refs/tags/${tag_ref}"
    git checkout -q "tags/${tag_ref}"
    resolved_ref="tag:${tag_ref}"
else
    for candidate in "$APP_VERSION" "v$APP_VERSION"; do
        if git_with_auth ls-remote --exit-code --heads origin "refs/heads/${candidate}" >/dev/null 2>&1; then
            branch_ref="$candidate"
            break
        fi
    done
    if [[ -n "$branch_ref" ]]; then
        log "🌿 Usando branch da aplicação: $branch_ref"
        git_with_auth fetch --depth 1 origin "refs/heads/${branch_ref}:refs/remotes/origin/${branch_ref}"
        git checkout -q "origin/${branch_ref}"
        resolved_ref="branch:${branch_ref}"
    else
        log_error "Versão da aplicação '${APP_VERSION}' não encontrada como tag nem branch no repositório."
        log_error "Tentativas realizadas: '${APP_VERSION}' e 'v${APP_VERSION}'."
        popd >/dev/null
        exit 1
    fi
fi

log_success "Ref da aplicação resolvida: ${resolved_ref}"

if [[ -x "./mvnw" ]]; then
    log "🔨 Build com Maven Wrapper"
    ./mvnw -DskipTests package
    build_ok=true
elif [[ -f "pom.xml" ]]; then
    if command -v mvn >/dev/null 2>&1; then
        log "🔨 Build com Maven"
        mvn -DskipTests package
        build_ok=true
    else
        log_warning "Maven não encontrado no agente."
    fi
elif [[ -x "./gradlew" ]]; then
    log "🔨 Build com Gradle Wrapper"
    ./gradlew clean bootWar war -x test || ./gradlew clean war -x test
    build_ok=true
elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
    if command -v gradle >/dev/null 2>&1; then
        log "🔨 Build com Gradle"
        gradle clean bootWar war -x test || gradle clean war -x test
        build_ok=true
    else
        log_warning "Gradle não encontrado no agente."
    fi
fi

if [[ "$build_ok" != "true" ]]; then
    log_warning "Nenhuma ferramenta de build encontrada. Tentando localizar WAR pré-gerado."
fi

mapfile -t war_candidates < <(
    find "$REPO_DIR" -type f -name "*.war" \
        ! -name "*sources*.war" \
        ! -name "*javadoc*.war" \
        -print | sort
)

if [[ "${#war_candidates[@]}" -eq 0 ]]; then
    log_error "Nenhum arquivo WAR encontrado após clone/build."
    popd >/dev/null
    exit 1
fi

selected_war="${war_candidates[0]}"
if [[ "${#war_candidates[@]}" -gt 1 ]]; then
    selected_war="$(ls -t "${war_candidates[@]}" | head -n1)"
fi

mkdir -p "$(dirname "$OUTPUT_WAR")"
cp "$selected_war" "$OUTPUT_WAR"
popd >/dev/null

log_success "WAR preparado com sucesso: $OUTPUT_WAR"
