# config.sh - optional defaults for gitlab-tools, sourced by lib.sh when
# present (same directory). Safe to edit: every assignment only fills an
# unset/empty variable, so values exported into the environment before a
# script runs always win:
#
#   env > config.sh > built-in defaults in lib.sh
#
# Location-independent: defaults resolve relative to this file's directory,
# so the toolkit works from any checkout/deployment path.
#
# GITLAB_HOST             instance host for every glab api call
# GITLAB_DEFAULT_PROJECT  <project> positional may be omitted when set
#                         (the remaining positionals shift left)
# GITLAB_TOOLS_STATE_DIR  directory for --state marker files given as a bare
#                         filename (mr-updates.sh); created on demand
# GITLAB_COMMENT_PREFIX   prefix every machine-generated comment must start
#                         with; write scripts refuse bodies without it and the
#                         --ai-only filters select by it (R12.5). Prescribed
#                         per host/repository by its owner; unset keeps the
#                         built-in default of lib.sh:
# GITLAB_COMMENT_PREFIX="[ai] "

_gt_tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GITLAB_HOST:=gitlab.corp.mail.ru}"
: "${GITLAB_DEFAULT_PROJECT:=}"
: "${GITLAB_TOOLS_STATE_DIR:=$_gt_tools_dir/.state}"
unset _gt_tools_dir
