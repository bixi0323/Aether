# Agent Instructions

## Build Resource Constraints

- This host has limited resources. Do not run `cargo build`, `cargo test`, `cargo clippy`, Docker builds, image builds, or other commands that can consume substantial CPU, memory, or disk unless the user explicitly approves that specific verification step.
- Do not install Rust, Node.js, system compiler dependencies, or other large toolchains without explicit user approval.
- Prefer static inspection and formatting-only checks. Delegate compilation and test execution to a remote environment or CI designated by the user.
- Do not leave `target/`, `node_modules/`, build caches, temporary worktrees, or other generated artifacts behind. Clean up anything created during the task.
- Before running any command likely to take more than 30 seconds or consume significant resources, ask the user first.
