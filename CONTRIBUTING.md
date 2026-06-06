# Contributing

## Workflow

1. Open a branch for your change.
2. Make the change in focused commits.
3. Run the local validation commands.
4. Open a pull request against the default branch.

## Validation

- `MIX_ENV=test mix deps.get`
- `mix dialyzer`
- `mix credo`
- `MIX_ENV=test mix coveralls.json`

## Review Expectations

- keep pull requests focused
- respond to review comments with follow-up commits or explicit reasoning
- prefer rebasing over merge commits
