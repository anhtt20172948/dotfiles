# Include account B in quota-axi alongside the selected Claude account and Codex.
case :${QUOTA_AXI_CLAUDE_PROFILES:-}: in
  *:"$HOME/.claude-b":*) ;;
  *) QUOTA_AXI_CLAUDE_PROFILES="${QUOTA_AXI_CLAUDE_PROFILES:+$QUOTA_AXI_CLAUDE_PROFILES:}$HOME/.claude-b" ;;
esac
export QUOTA_AXI_CLAUDE_PROFILES
