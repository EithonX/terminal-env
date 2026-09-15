#!/usr/bin/env bash
set -Eeuo pipefail
repo=${TERMINAL_ENV_REPO:-https://github.com/EithonX/terminal-env.git}
source_name=${repo#https://github.com/}
source_name=${source_name%.git}
branch=${TERMINAL_ENV_BRANCH:-master}
profile=${TERMINAL_ENV_PROFILE:-auto}
dry_run=0
format=human
color=auto
quiet=0
verbose=0
args=()
usage(){ printf '%s\n' 'Usage: bootstrap.sh [--profile auto|server|workstation|minimal] [--branch NAME] [installer options]'; }
bootstrap_progress(){
  (( quiet )) && return 0
  if [[ $format == human || $verbose == 1 ]]; then printf '%s\n' "$*" >&2; fi
}
while (($#)); do
  case "$1" in
    --profile) profile=${2:?missing profile}; args+=(--profile "$2"); shift 2 ;;
    --branch) branch=${2:?missing branch}; shift 2 ;;
    --dry-run) dry_run=1; args+=(--dry-run); shift ;;
    --no-shell-change|--no-font|--force) args+=("$1"); shift ;;
    --format) (($# >= 2)) || { printf '%s\n' 'Missing value for --format.' >&2; exit 2; }; format=$2; args+=(--format "$2"); shift 2 ;;
    --format=*) format=${1#*=}; args+=("$1"); shift ;;
    --color) (($# >= 2)) || { printf '%s\n' 'Missing value for --color.' >&2; exit 2; }; color=$2; args+=(--color "$2"); shift 2 ;;
    --color=*) color=${1#*=}; args+=("$1"); shift ;;
    --quiet) quiet=1; args+=(--quiet); shift ;;
    --verbose) verbose=1; args+=(--verbose); shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$profile" in auto|server|workstation|minimal) ;; *) printf 'Invalid profile: %s\n' "$profile" >&2; exit 2 ;; esac
case "$format" in human|plain|json) ;; *) printf 'Invalid format: %s\n' "$format" >&2; exit 2 ;; esac
case "$color" in auto|always|never) ;; *) printf 'Invalid color mode: %s\n' "$color" >&2; exit 2 ;; esac
(( quiet == 0 || verbose == 0 )) || { printf '%s\n' '--quiet and --verbose cannot be used together.' >&2; exit 2; }
[[ $branch =~ ^[A-Za-z0-9._/-]+$ && $branch != *'../'* && $branch != '../'* && $branch != *'/..' ]] || { printf 'Invalid branch name.\n' >&2; exit 2; }
if [[ $EUID -eq 0 && -n ${SUDO_USER:-} && ${SUDO_USER:-root} != root ]]; then printf 'Do not run Terminal Environment with sudo. Run it as your user.\n' >&2; exit 1; fi
os=$(uname -s)
case "$os" in Darwin|Linux) ;; *) printf 'Unsupported platform: %s\n' "$os" >&2; exit 1 ;; esac
if [[ $os == Linux ]] && ! command -v apt-get >/dev/null 2>&1; then printf 'Linux bootstrap currently supports Ubuntu/Debian with apt-get.\n' >&2; exit 1; fi
if (( ! quiet )) && [[ $format == human ]]; then
  printf '%s\n' 'Terminal Environment'
  printf '  source  %s@%s\n' "$source_name" "$branch"
  printf '  profile %s\n' "$profile"
fi
if [[ $os == Darwin ]] && { ! command -v brew >/dev/null 2>&1 || ! brew --version >/dev/null 2>&1; }; then
  if (( dry_run )); then printf 'Homebrew is not installed. Bootstrap dry-run does not install prerequisites.\n' >&2; exit 1; fi
  command -v curl >/dev/null 2>&1 || { printf 'curl is required to install Homebrew.\n' >&2; exit 1; }
  tmp_brew=$(mktemp -d 2>/dev/null || mktemp -d -t terminal-env-brew)
  trap 'rm -rf -- "$tmp_brew"' EXIT INT TERM
  bootstrap_progress 'Preparing Homebrew prerequisite...'
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 1 -o "$tmp_brew/install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  if [[ -r /dev/tty ]]; then /bin/bash "$tmp_brew/install.sh" </dev/tty 1>&2; else NONINTERACTIVE=1 /bin/bash "$tmp_brew/install.sh" 1>&2; fi
  rm -rf -- "$tmp_brew"
  trap - EXIT INT TERM
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew >/dev/null 2>&1 && brew --version >/dev/null 2>&1 || { printf 'Homebrew installation completed but brew is unavailable in this shell.\n' >&2; exit 1; }
fi
if ! command -v git >/dev/null 2>&1 || ! git --version >/dev/null 2>&1; then
  if (( dry_run )); then printf 'Git is not installed. Bootstrap dry-run does not install prerequisites.\n' >&2; exit 1; fi
  if [[ $os == Linux ]]; then
    sudo_cmd=()
    if (( EUID != 0 )); then command -v sudo >/dev/null 2>&1 || { printf 'sudo is required to install Git.\n' >&2; exit 1; }; sudo_cmd=(sudo); fi
    bootstrap_progress 'Preparing Git prerequisite...'
    "${sudo_cmd[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update 1>&2
    "${sudo_cmd[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates 1>&2
  else
    brew install git 1>&2
  fi
  command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1 || { printf 'Git installation completed but git is unavailable in this shell.\n' >&2; exit 1; }
fi
tmp=$(mktemp -d 2>/dev/null || mktemp -d -t terminal-env)
cleanup(){ rm -rf -- "$tmp"; }
trap cleanup EXIT INT TERM
bootstrap_progress 'Fetching source...'
cloned=0
for attempt in 1 2 3; do
  rm -rf -- "$tmp/repo"
  if git clone --quiet --depth 1 --single-branch --branch "$branch" -- "$repo" "$tmp/repo"; then cloned=1; break; fi
  (( attempt < 3 )) && sleep $((attempt*2))
done
(( cloned )) || { printf 'Could not clone %s@%s.\n' "$source_name" "$branch" >&2; exit 1; }
checked_out=$(git -C "$tmp/repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ $checked_out == "$branch" ]] || { printf "'%s' is not an updateable branch.\n" "$branch" >&2; exit 1; }
[[ -f $tmp/repo/install.sh ]] || { printf 'Cloned repository does not contain install.sh.\n' >&2; exit 1; }
if ((${#args[@]})); then
  bash "$tmp/repo/install.sh" "${args[@]}"
else
  bash "$tmp/repo/install.sh"
fi
