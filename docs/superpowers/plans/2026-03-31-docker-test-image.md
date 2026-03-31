# Docker Test Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Ubuntu-based Docker test image that runs as a normal user without sudo and can be used to validate the remote installer flow.

**Architecture:** Add a single `Dockerfile.test` that installs the installer prerequisites at build time, creates a non-root `tester` user, and defaults to `bash`. Update `README.md` with short build-and-run instructions so manual and one-shot Docker tests are obvious from the repository root.

**Tech Stack:** Docker, Ubuntu 24.04, Bash, apt

---

## File Structure

**Create:**
- `Dockerfile.test`

**Modify:**
- `README.md`

### Task 1: Add Docker Test Image Definition

**Files:**
- Create: `Dockerfile.test`
- Test: `Dockerfile.test`

- [ ] **Step 1: Write a failing build attempt command**

Run: `docker build -t eric-dev-workbench-test -f Dockerfile.test .`
Expected: FAIL with `failed to read dockerfile` because `Dockerfile.test` does not exist yet.

- [ ] **Step 2: Create `Dockerfile.test` with the minimal non-root Ubuntu test image**

```dockerfile
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    ca-certificates \
    xz-utils \
    tar \
    gzip \
    file \
    make \
    gcc \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash tester

USER tester
WORKDIR /home/tester
CMD ["bash"]
```

- [ ] **Step 3: Run the Docker build to verify it passes**

Run: `docker build -t eric-dev-workbench-test -f Dockerfile.test .`
Expected: PASS and the image is tagged as `eric-dev-workbench-test`.

- [ ] **Step 4: Verify the container runs as the expected non-root user**

Run: `docker run --rm eric-dev-workbench-test bash -lc 'whoami'`
Expected: `tester`

- [ ] **Step 5: Verify `sudo` is unavailable**

Run: `docker run --rm eric-dev-workbench-test bash -lc 'command -v sudo || echo no-sudo'`
Expected: `no-sudo`

- [ ] **Step 6: Commit**

```bash
git add Dockerfile.test
git commit -m "test: add ubuntu docker image for non-root installer checks"
```

### Task 2: Document Docker Test Workflow

**Files:**
- Modify: `README.md`
- Test: `README.md`

- [ ] **Step 1: Write the failing docs expectation by checking README for Docker instructions**

Run: `grep -n "Dockerfile.test" README.md`
Expected: FAIL with exit code `1` because the Docker test image is not documented yet.

- [ ] **Step 2: Add a short Docker testing section to `README.md`**

```markdown
## Docker Test Image

Build the Ubuntu non-root test image:

```bash
docker build -t eric-dev-workbench-test -f Dockerfile.test .
```

Start an interactive shell as the normal `tester` user:

```bash
docker run --rm -it eric-dev-workbench-test bash
```

Run the remote installer directly in one shot:

```bash
docker run --rm -it eric-dev-workbench-test \
  bash -lc 'curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install'
```
```

- [ ] **Step 3: Verify the README now contains the Docker instructions**

Run: `grep -n "Dockerfile.test" README.md`
Expected: PASS and prints the matching line.

- [ ] **Step 4: Verify the one-shot container command can start the installer**

Run: `docker run --rm eric-dev-workbench-test bash -lc 'curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- --help'`
Expected: PASS and prints the installer usage text.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add docker-based installer test workflow"
```

## Self-Review

Spec coverage:
- Non-root Ubuntu test image: Task 1
- Required build dependencies: Task 1
- Interactive and one-shot usage: Task 2
- Verification that the image runs as `tester` with no `sudo`: Task 1

Placeholder scan:
- No `TODO`, `TBD`, or implied follow-up steps remain.

Type consistency:
- File names, image tag, and runtime user are consistent across both tasks.
