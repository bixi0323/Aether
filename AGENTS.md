# Agent Instructions

## Build and Test Policy

This checkout runs on a production host with limited disk capacity.

- Do not run local builds, compilation, or test suites on this host, including
  `cargo build`, `cargo test`, frontend builds, and Docker image builds.
- Do not pull large toolchain images or create large `target`, Cargo, npm, or
  Docker build-cache directories here.
- Use GitHub Actions for builds and tests. The image build workflow is
  `.github/workflows/build-pr-818.yml` and is started with `workflow_dispatch`.
- Commit and push the intended source changes before dispatching the workflow so
  the remote build does not run against a stale branch.
- Static source inspection, log inspection, `git diff --check`, and lightweight
  checks against an already running service are allowed.
- If temporary files are created accidentally, remove them immediately and keep
  the production host's free disk space healthy.
