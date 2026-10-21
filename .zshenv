# Reload the selected token for interactive and non-interactive worker shells.
# Keep token reads out of xtrace and avoid leaking temporary variables.
() {
  setopt localoptions noxtrace
  local accounts=$HOME/.config/claude-accounts account token
  [[ -r $accounts/active ]] || return 0
  account=$(<$accounts/active)
  # Same name rule as ai-acct.
  [[ $account =~ '^[a-z0-9][a-z0-9_-]{0,31}$' ]] || { unset CLAUDE_CODE_OAUTH_TOKEN AI_ACCT_FINGERPRINT; return 0; }
  [[ -f $accounts/$account.token && -r $accounts/$account.token ]] || {
    unset CLAUDE_CODE_OAUTH_TOKEN AI_ACCT_FINGERPRINT
    return 0
  }
  token=$(<$accounts/$account.token)
  # Same token rule as ai-acct.
  [[ $token =~ '^[A-Za-z0-9._~+/=-]+$' ]] || { unset CLAUDE_CODE_OAUTH_TOKEN AI_ACCT_FINGERPRINT; return 0; }
  unset CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY
  export CLAUDE_CODE_OAUTH_TOKEN=$token
  # Same fingerprint as ai-acct; Claude Code hides the token from statuslines.
  local fp
  fp=$(print -rn -- "ai-acct-statusline:$token" | { sha256sum 2>/dev/null || shasum -a 256 })
  export AI_ACCT_FINGERPRINT=${fp%% *}
}

# Load the fleet-deck Claude Code mod (.config/claude-mods/fleet-deck). Only a
# path is added, no secret is read; skipped where the checkout is absent and
# when the path is already listed (nested shells source this file again).
() {
  local mod=$HOME/.config/claude-mods/fleet-deck
  [[ -d $mod && :${CLAUDE_CODE_PLUGIN_DIRS-}: != *:$mod:* ]] || return 0
  export CLAUDE_CODE_PLUGIN_DIRS=${CLAUDE_CODE_PLUGIN_DIRS:+$CLAUDE_CODE_PLUGIN_DIRS:}$mod
}
