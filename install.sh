#!/usr/bin/env bash
# NEXYRA Automation — bootstrap independente do distribuidor VPS
# Versao: 3.3.0-R2, release privada publicada sob controle do usuario.
# Publicavel em um repositorio PUBLICO: NAO contem codigo privativo nem segredos.
set -Eeuo pipefail
umask 077

readonly REPO='nexyratechoficial-jpg/nexyra-automationbot'
readonly TAG='v3.3.0-R2'
readonly ASSET='NEXYRA-R2.zip'
readonly SHA256='896dd65ef1f6b303201dc44949b3567efcd340e93450aae37375bf4ddc857883'

fail() { printf '\n[NEXYRA ERRO] %s\n' "$*" >&2; exit 1; }
info() { printf '\n[NEXYRA] %s\n' "$*"; }

[[ "$EUID" -eq 0 ]] || fail 'Conecte como root na VPS NOVA antes de executar.'
[[ ! -e /opt/nexyra-cliente ]] || fail 'Esta VPS ja possui /opt/nexyra-cliente. Nao sobrescrever.'
[[ -r /etc/os-release ]] || fail 'Nao foi possivel identificar o sistema operacional.'
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
  ubuntu:22.04|ubuntu:24.04|debian:12|debian:13) ;;
  *) fail "Sistema nao homologado: ${PRETTY_NAME:-desconhecido}. Use Ubuntu 22.04/24.04 ou Debian 12/13." ;;
esac
[[ "$(uname -m)" == 'x86_64' ]] || fail 'Arquitetura nao suportada. Requer x86_64.'
[[ "$(nproc)" -ge 2 ]] || fail 'A VPS precisa de pelo menos 2 vCPUs.'
command -v curl >/dev/null || fail 'curl indisponivel.'
command -v sha256sum >/dev/null || fail 'sha256sum indisponivel.'
command -v python3 >/dev/null || fail 'python3 indisponivel.'
command -v apt-get >/dev/null || fail 'apt-get indisponivel.'

# Evitar download/instalacao em ambiente parcialmente instalado ou com outra aplicacao nas portas.
if command -v ss >/dev/null; then
  if ss -H -ltn '( sport = :80 or sport = :443 )' 2>/dev/null | grep -q .; then
    fail 'Porta 80 ou 443 ocupada. Identifique o servico antes da instalacao.'
  fi
fi

info "NEXYRA R2 | repositorio privado: $REPO | release: $TAG"
info 'Esta rotina busca o ZIP do GitHub. A validacao da licenca ainda depende do MASTER.'

if ! command -v gh >/dev/null 2>&1; then
  info 'Instalando GitHub CLI (gh) pelo gerenciador oficial do Ubuntu/Debian...'
  DEBIAN_FRONTEND=noninteractive apt-get update -qq || fail 'Falha no apt-get update.'
  DEBIAN_FRONTEND=noninteractive apt-get install -y gh ca-certificates || fail 'Falha ao instalar o GitHub CLI.'
fi

# Token digitado sem eco; nao salvo em arquivo de credenciais do GitHub nem no historico de shell.
# Criar conta/token de acesso fino limitado a ESTE repositorio, Contents: Read-only.
[[ -t 0 ]] || fail 'Execute em terminal interativo (Termius/SSH).'
printf '\n'
printf 'Cole o token GitHub com acesso de LEITURA ao repositorio privado.\n'
IFS= read -r -s -p 'Token GitHub (nao aparece na tela): ' gh_token
printf '\n'
[[ -n "$gh_token" ]] || fail 'Token vazio.'

workdir="$(mktemp -d /root/.nexyra-bootstrap-r2.XXXXXXXX)" || fail 'Nao foi possivel criar diretorio temporario.'
cleanup() {
  unset gh_token || true
  if [[ -n "${workdir:-}" && -d "$workdir" ]]; then rm -rf -- "$workdir"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

info 'Baixando pacote privado do GitHub (o token nao sera gravado)...'
if ! GH_TOKEN="$gh_token" GH_PROMPT_DISABLED=1 gh release download "$TAG" \
    -R "$REPO" -p "$ASSET" -D "$workdir" --clobber; then
  fail 'Download falhou. Confira token, permissao Contents: Read-only, repositorio e release.'
fi
unset gh_token

zip_file="$workdir/$ASSET"
[[ -f "$zip_file" ]] || fail "Arquivo esperado nao encontrado: $ASSET"
printf '%s  %s\n' "$SHA256" "$zip_file" | sha256sum -c - \
  || fail 'Hash SHA-256 incorreto. Instalacao BLOQUEADA. Nao execute este pacote.'
info 'ZIP R2 autenticado, baixado e SHA-256 confirmado.'

extract_dir="$workdir/kit"
mkdir -p "$extract_dir"
python3 - "$zip_file" "$extract_dir" <<'PY'
from pathlib import Path
import stat, sys, zipfile
source = Path(sys.argv[1]); target = Path(sys.argv[2]).resolve()
with zipfile.ZipFile(source) as archive:
    records = archive.infolist()
    if len(records) > 300: raise SystemExit('ZIP contem muitos arquivos')
    if sum(x.file_size for x in records) > 250_000_000: raise SystemExit('ZIP descompactado grande demais')
    for member in records:
        path = (target / member.filename).resolve()
        if path != target and target not in path.parents: raise SystemExit('Entrada ZIP insegura')
        if stat.S_ISLNK(member.external_attr >> 16): raise SystemExit('ZIP contem link simbolico')
    archive.extractall(target)
PY

[[ -f "$extract_dir/VERIFICAR-INTEGRIDADE.sh" ]] || fail 'Validador ausente no kit.'
[[ -f "$extract_dir/INSTALAR-REVENDEDOR-DO-ZIP.sh" ]] || fail 'Instalador local ausente no kit.'

cd "$extract_dir"
info 'Verificando arquivos internos...'
bash ./VERIFICAR-INTEGRIDADE.sh || fail 'Verificacao interna falhou.'
info 'Iniciando instalacao do revendedor...'
info 'Serao solicitados dominio base, ID da VPS e token da LICENCA (nao o GitHub).'
bash ./INSTALAR-REVENDEDOR-DO-ZIP.sh || fail 'Instalador retornou erro. Nao refaca sem analisar o motivo.'
info 'Instalador finalizado. Teste acesso HTTPS, painel, integracoes e rotina de backup.'
