# Docker Test Image Design

## Summary

Add a dedicated Docker test image for validating the installer in a Linux environment that matches the intended non-root deployment path.

The image will be:

- based on `ubuntu:24.04`
- provisioned with installer prerequisites during image build
- run as a normal user named `tester`
- intentionally without `sudo`

The image is intended to support both:

- interactive manual testing
- one-shot execution of the remote `curl | bash` installer command

## Goals

- Provide a reproducible Ubuntu test environment for the installer
- Validate the non-root install path under a normal user account
- Avoid mutating a real host while testing installer behavior
- Keep the image minimal and focused on installer validation

## Non-Goals

- Replacing real macOS testing
- Testing every runtime behavior of `mihomo` networking inside Docker
- Building a full CI pipeline in this change
- Providing root or `sudo` during test execution

## Design

### Image behavior

The repository will add a single test-specific Dockerfile, named `Dockerfile.test`.

Build-time behavior:

- Start from `ubuntu:24.04`
- Install required packages with `apt-get`
- Create a regular user `tester`
- Set the container default user to `tester`
- Set the default working directory to `/home/tester`

Run-time behavior:

- Default command remains `bash`
- Users can start an interactive shell and run installer commands manually
- Users can also override the command to run the remote installer directly

### Installed dependencies

The image should include the minimum tools required for realistic installer testing:

- `bash`
- `curl`
- `git`
- `ca-certificates`
- `xz-utils`
- `tar`
- `gzip`
- `file`
- `make`
- `gcc`

These cover:

- remote bootstrap via `curl`
- repository bootstrap via `git clone`
- user-space zsh build path
- basic binary inspection during debugging

### Usage

Interactive usage:

```bash
docker build -t eric-dev-workbench-test -f Dockerfile.test .
docker run --rm -it eric-dev-workbench-test bash
```

Inside the container:

```bash
whoami
curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install
```

One-shot usage:

```bash
docker run --rm -it eric-dev-workbench-test \
  bash -lc 'curl -fsSL https://raw.githubusercontent.com/BLUELOVEREST/eric-dev-workbench/main/install.sh | bash -s -- install'
```

## Documentation Update

`README.md` should gain a short section describing:

- what `Dockerfile.test` is for
- how to build it
- how to enter it as the non-root user
- how to run the remote installer inside it

## Verification

At minimum, verify:

1. `docker build -t eric-dev-workbench-test -f Dockerfile.test .` succeeds
2. `docker run --rm -it eric-dev-workbench-test bash -lc 'whoami'` prints `tester`
3. The container has no `sudo`
4. The remote installer command can be executed from inside the container

## Result

After this change, the repository will provide a clean Ubuntu test target for validating the installer's non-root Linux path without requiring changes to a real machine.
