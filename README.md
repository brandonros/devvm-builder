# devvm-builder

NixOS aarch64 qcow2 image for QEMU, built reproducibly from a flake (locally or in CI).

## Setup

Drop your SSH public key into [keys/user.pub](keys/user.pub) (one per line, `#` comments allowed).

## Build

### In CI (recommended)

Push to `main` or run the workflow manually — [.github/workflows/ci.yaml](.github/workflows/ci.yaml) builds on `ubuntu-24.04-arm` and uploads `devvm-aarch64/main.qcow2.zst` as a workflow artifact.

### Locally on Linux aarch64

```bash
nix build .#devvm
ls -lh result/
```

### Locally on macOS aarch64

Nix builds need Linux. Either set up a `linux-builder` (via nix-darwin) or use the CI artifact.

## Run

```bash
zstd -d main.qcow2.zst -o devvm.qcow2

QEMU_SHARE="$(dirname "$(readlink -f "$(command -v qemu-system-aarch64)")")/../share/qemu"
qemu-system-aarch64 \
  -machine virt,accel=hvf,highmem=on \
  -cpu host -smp 4 -m 8G \
  -bios "$QEMU_SHARE/edk2-aarch64-code.fd" \
  -drive if=virtio,file=devvm.qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

SSH in: `ssh -p 2222 user@localhost` (key auth; password `foobar123` for sudo).
