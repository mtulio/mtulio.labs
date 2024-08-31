#!/usr/bin/env bash

yq -j ea '.jobs["CloudFormation"]' .github/workflows/linters.yaml  \
  | jq -r '.steps[] | select(.name=="Run").run' | bash