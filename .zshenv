# Reload the selected token for interactive and non-interactive worker shells.
# Keep token reads out of xtrace and avoid leaking temporary variables.
() {
  setopt localoptions noxtrace
  local accounts=$HOME/.config/claude-accounts account token
  [[ -r $accounts/active ]] || return 0
  account=$(<$accounts/active)
  # Same name rule as ai-acct.
  [[ $account =~ '^[a-z0-9][a-z0-9_-]{0,31}$' ]] || { unset CLAUDE_CODE_OAUTH_TOKEN; return 0; }
  [[ -f $accounts/$account.token && -r $accounts/$account.token ]] || {
    unset CLAUDE_CODE_OAUTH_TOKEN
    return 0
  }
  token=$(<$accounts/$account.token)
  # Same token rule as ai-acct.
  [[ $token =~ '^[A-Za-z0-9._~+/=-]+$' ]] || { unset CLAUDE_CODE_OAUTH_TOKEN; return 0; }
  unset CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY
  export CLAUDE_CODE_OAUTH_TOKEN=$token
}
