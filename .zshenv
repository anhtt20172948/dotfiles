# Reload the selected token for interactive and non-interactive worker shells.
# Keep token reads out of xtrace and avoid leaking temporary variables.
() {
  setopt localoptions noxtrace
  local accounts=$HOME/.config/claude-accounts account token
  [[ -r $accounts/active ]] || return 0
  account=$(<$accounts/active)
  case $account in a|b) ;; *) unset CLAUDE_CODE_OAUTH_TOKEN; return 0 ;; esac
  [[ -f $accounts/$account.token && -r $accounts/$account.token ]] || {
    unset CLAUDE_CODE_OAUTH_TOKEN
    return 0
  }
  token=$(<$accounts/$account.token)
  case $token in ''|*[![:graph:]]*) unset CLAUDE_CODE_OAUTH_TOKEN; return 0 ;; esac
  unset CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY
  export CLAUDE_CODE_OAUTH_TOKEN=$token
}
