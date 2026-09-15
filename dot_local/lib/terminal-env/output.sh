# shellcheck shell=bash

TE_UI_TEXT='#E6EBF0'
TE_UI_SOFT='#A2ACB7'
TE_UI_MUTED='#707C88'
TE_UI_ACCENT='#7CC4E4'
TE_UI_WARNING='#D6A85F'
TE_UI_DANGER='#E07880'
TE_UI_SUCCESS='#8BB594'
TE_UI_COLOR=0
TE_UI_WIDTH=80

te_ui_clean_text() {
  printf '%s' "${1-}" | LC_ALL=C tr '\000-\037\177' ' '
}

te_ui_hex_escape() {
  local hex=${1#\#} r g b
  r=${hex:0:2}; g=${hex:2:2}; b=${hex:4:2}
  printf '\033[38;2;%d;%d;%dm' "$((16#$r))" "$((16#$g))" "$((16#$b))"
}

te_ui_init() {
  local format=${1:-human} color=${2:-auto} width=''
  TE_UI_COLOR=0
  if [[ $format == human ]]; then
    case "$color" in
      always) TE_UI_COLOR=1 ;;
      never) TE_UI_COLOR=0 ;;
      auto)
        if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
          TE_UI_COLOR=1
        fi
        ;;
      *) return 2 ;;
    esac
  fi

  width=${COLUMNS:-}
  if [[ ! $width =~ ^[0-9]+$ || $width -le 0 ]]; then
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
      width=$(tput cols 2>/dev/null || true)
    fi
  fi
  [[ $width =~ ^[0-9]+$ && $width -gt 0 ]] || width=80
  TE_UI_WIDTH=$width
}

te_ui_style() {
  local role=$1 text color=''
  text=$(te_ui_clean_text "${2-}")
  if (( ! TE_UI_COLOR )); then
    printf '%s' "$text"
    return
  fi
  case "$role" in
    title) printf '\033[1m%s\033[0m' "$text"; return ;;
    text) color=$TE_UI_TEXT ;;
    soft) color=$TE_UI_SOFT ;;
    muted) color=$TE_UI_MUTED ;;
    accent) color=$TE_UI_ACCENT ;;
    warning) color=$TE_UI_WARNING ;;
    danger) color=$TE_UI_DANGER ;;
    success) color=$TE_UI_SUCCESS ;;
    *) printf '%s' "$text"; return ;;
  esac
  te_ui_hex_escape "$color"
  printf '%s\033[0m' "$text"
}

te_ui_title() {
  te_ui_style title "Terminal Environment · $1"
  printf '\n'
}

te_ui_meta() {
  te_ui_style muted "$1"
  printf '\n'
}

te_ui_section() {
  printf '\n'
  te_ui_style title "$1"
  printf '\n'
}

te_ui_row() {
  local label=$1 value=${2-} tone=${3:-text} width
  if (( TE_UI_WIDTH < 72 )); then
    printf '  '
    te_ui_style soft "$label"
    printf '\n    '
    te_ui_style "$tone" "$value"
    printf '\n'
    return
  fi
  if (( TE_UI_WIDTH >= 100 )); then width=20; else width=16; fi
  printf '  '
  te_ui_style soft "$(printf '%-*s' "$width" "$label")"
  printf '  '
  te_ui_style "$tone" "$value"
  printf '\n'
}

te_ui_attention() {
  local status=$1 label=$2 message=$3 word tone width
  case "$status" in
    fail|failure) word='failure'; tone='danger' ;;
    *) word='warning'; tone='warning' ;;
  esac
  if (( TE_UI_WIDTH < 72 )); then
    printf '  '
    te_ui_style soft "$label"
    printf '\n    '
    te_ui_style "$tone" "$word"
    printf ' · %s\n' "$message"
    return
  fi
  if (( TE_UI_WIDTH >= 100 )); then width=20; else width=16; fi
  printf '  '
  te_ui_style soft "$(printf '%-*s' "$width" "$label")"
  printf '  '
  te_ui_style "$tone" "$word"
  printf ' · %s\n' "$message"
}

te_ui_outcome() {
  local tone=$1 text=$2
  printf '\n'
  te_ui_style "$tone" "$text"
  printf '\n'
}

te_ui_json_string() {
  local s
  s=$(te_ui_clean_text "${1-}")
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}
