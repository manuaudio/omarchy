echo "Re-run the project bin PATH removal that a reused migration name skipped"

# 1789095456 first shipped as a Panther Lake kernel migration, was deleted a day
# later, and the name was then reused for the Mise PATH repair. Anyone who
# updated in between already holds the 1789095456 marker, so the repair never
# ran for them. Only re-run it where its leftover state proves that: running it
# again elsewhere would revoke Mise trust a user may have reviewed and granted.
work_mise_config="$HOME/Work/.mise.toml"
work_stock_sha="bd04f191d63bbde86920f44f76f0989fad980afc84e268e8474c201ec7149245"
work_cwd_bin='\{\{[[:space:]]*cwd[[:space:]]*\}\}/bin'
work_unsafe_path="^[[:space:]]*_[.]path[[:space:]]*=[[:space:]]*(\"$work_cwd_bin\"|'$work_cwd_bin')[[:space:]]*(#.*)?$"
work_env_section='^[[:space:]]*\[[[:space:]]*env[[:space:]]*\][[:space:]]*(#.*)?$'
work_any_section='^[[:space:]]*\[\[?.*\]\]?[[:space:]]*(#.*)?$'

[[ -f $work_mise_config ]] || exit 0

needs_repair=false
if [[ ! -L $work_mise_config && $(sha256sum "$work_mise_config" | cut -d ' ' -f 1) == $work_stock_sha ]]; then
  needs_repair=true
elif [[ -n $(sed -n -E "\\%$work_env_section%,\\%$work_any_section% { \\%$work_unsafe_path%p; }" "$work_mise_config") ]]; then
  needs_repair=true
fi

[[ $needs_repair == "true" ]] || exit 0

source "$OMARCHY_PATH/migrations/1789095456.sh"
