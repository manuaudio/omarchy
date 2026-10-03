#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_bin=$(mktemp -d)
log_file=$(mktemp)
stderr_file=$(mktemp)

cleanup() {
  rm -rf "$test_bin"
  rm -f "$log_file" "$stderr_file"
}
trap cleanup EXIT

# Esc in gum choose exits 1 with nothing selected.
cat >"$test_bin/gum" <<'STUB'
#!/bin/bash
cat >/dev/null
exit 1
STUB

for command in sudo docker; do
  cat >"$test_bin/$command" <<STUB
#!/bin/bash
echo "$command \$*" >>"\$TEST_LOG"
STUB
done
chmod +x "$test_bin"/*

status=0
TEST_LOG="$log_file" PATH="$test_bin:$PATH" "$ROOT/bin/omarchy-install-docker-dbs" >/dev/null 2>"$stderr_file" || status=$?

if grep -q "command not found" "$stderr_file"; then
  fail "cancelling the database picker runs no missing command" "$(cat "$stderr_file")"
fi
pass "cancelling the database picker runs no missing command"

if [[ -s $log_file ]]; then
  fail "cancelling the database picker starts no container" "$(cat "$log_file")"
fi
pass "cancelling the database picker starts no container"

if (( status != 130 )); then
  fail "cancelling the database picker exits 130 to skip the Done prompt" "exit status: $status"
fi
pass "cancelling the database picker exits 130 to skip the Done prompt"
