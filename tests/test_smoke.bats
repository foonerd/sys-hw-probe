#!/usr/bin/env bats

@test "orientation-audit-volumio.sh prints header" {
  run bash scripts/display/orientation-audit-volumio.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
