# GIX GPU cluster: admin guide

For IT staff who run the cluster. The student guide is the [README](../README.md) at the top of this repo.

## How it works

```
student laptop ──ssh──► gix-login (gix-30292619)
  VS Code Remote-SSH      └─ ProxyCommand: /usr/local/bin/gix-devjob
                               1. finds or submits the student's Slurm job "devc-<netid>"
                               2. waits until it runs, copies the student's SSH keys to the node
                               3. pipes the SSH connection to port 22 of that node (nc)
                          ──► GPU node (sshd)
                               pam_slurm_adopt puts the session into the job's cgroup
                               └─ VS Code Dev Containers → rootless Podman → GPU via CDI
```

Everything the student starts (VS Code server, Podman, the container) runs inside the Slurm job,
so the job's GPU, CPU and RAM limits apply. When the job ends, Slurm kills all of it.

### Machines

| Host | Role | Hardware |
|---|---|---|
| gix-30292619 | Slurm controller (`slurmctld`) and student login host (`gix-login`). Runs no jobs | RTX 5090 (not in Slurm) |
| gix-30292585, -620, -622 | GPU node | RTX 5090, 16 CPUs, ~110 GB RAM |
| gix-30292621, -627 | GPU node | RTX 5090, 24 CPUs, ~54 GB RAM |

All run Ubuntu 26.04, Slurm 25.11.2, cgroup v2, NetID logins through SSSD (AD `netid.washington.edu`).
Home directories are **local to each node**, not shared.

---

## Settings you can change

### Per-session defaults (`/usr/local/bin/gix-devjob` on the controller)

| Variable | Default | Meaning |
|---|---|---|
| `GIX_GRES` | `shard:1` | GPU share per session. `shard:1` = 1/4 GPU, `gpu:1` = whole GPU |
| `GIX_CPUS` | `4` | CPUs per session |
| `GIX_MEM` | `12G` | RAM per session (4 × 12G fits the 54 GB nodes) |
| `GIX_TIME` | `04:00:00` | Session length. After this the job ends and VS Code disconnects |
| `GIX_IDLE_MIN` | `30` | Job ends after this many minutes with no SSH session from the student. `0` = never |
| `GIX_PART` | `gpu` | Slurm partition |
| `GIX_NODE` | (none) | Pin to one node (waits for it) |
| `GIX_PREFER_NODE` | (none) | Use this node if it is free right now, else any node |

To change a default for everyone, edit the `${GIX_…:-default}` line near the top of the script:

```sh
sudo nano /usr/local/bin/gix-devjob      # e.g. TIME="${GIX_TIME:-08:00:00}"
```

No restart needed; it applies to the next connection. Running sessions keep their old limits.

One student can override a value in their own `~/.ssh/config` on the laptop:

```
ProxyCommand ssh -q gix-login "GIX_TIME=08:00:00 GIX_GRES=gpu:1 /usr/local/bin/gix-devjob"
```

> Slurm still enforces its own limits (partition `MaxTime`, available GRES), so an override
> can't go beyond what Slurm allows.

### Slurm (`/etc/slurm/` on the controller and every node, must be identical)

| What | Where | Now |
|---|---|---|
| Shards per GPU | `gres.conf` (`Name=shard Count=4`) and `Gres=gpu:1,shard:4` on each `NodeName` in `slurm.conf` | 4 |
| Max job length | `PartitionName=gpu … MaxTime=` | `INFINITE` |
| Nodes in the partition | `PartitionName=gpu Nodes=` | the 5 GPU nodes |
| Job prolog | `Prolog=/etc/slurm/gix-prolog.sh` | see below |

After editing `slurm.conf` or `gres.conf`:

```sh
# copy the same file to every node, then on the controller:
sudo scontrol reconfigure
# a changed GRES/shard count needs: sudo systemctl restart slurmctld, then slurmd on each node
sinfo -N -o "%N %T %G"      # check
```

Recommended additions (not set yet):

- `MaxTime=12:00:00` on the partition, so nobody can request days.
- `DefMemPerCPU=…`, so a job without `--mem` doesn't take the whole node's RAM.

---

## What is installed on each GPU node

| Part | Files | Purpose |
|---|---|---|
| PAM | `/etc/pam.d/sshd`, `/etc/security/access-gix.conf`, `/etc/pam.d/gix-sshd-session` | Users without a job on the node are refused (`pam_slurm_adopt`); accounts in `access-gix.conf` (admins) can always log in. `pam_systemd` is off for sshd so sessions stay in the job cgroup |
| Slurm prolog | `/etc/slurm/gix-prolog.sh` | At job start (as root): creates a missing home dir, resets stale rootless-Podman state, gives new users a subuid/subgid range |
| Podman | `/etc/containers/containers.conf` | `cgroups = "disabled"`: containers stay in the job cgroup |
| | `/etc/containers/storage.conf`, `storage-user.conf`, `/etc/ssh/sshd_config.d/gix-podman.conf` | Per-user image storage in `/var/lib/gix-containers/<user>/` (local disk) |
| | `podman-docker` | `docker` command = rootless Podman. There is no Docker daemon |
| GPU in containers | `nvidia-container-toolkit`, `/etc/cdi/nvidia.yaml` | Containers use `--device=nvidia.com/gpu=all`. `nvidia-cdi-refresh` regenerates the CDI file after driver updates |
| Environment | `/etc/profile.d/gix-devcontainer.sh`, `/etc/gix/ros_domain_ids` | One `ROS_DOMAIN_ID` per student (`netid id` per line) |

Setup scripts for all of this: `~/cluster-work/rollout/` on the controller (also copied to `~/gix-rollout/` on each node).
Every changed file has a backup next to it (`*.orig-gix`, `*.bak-<timestamp>`) or in `/root/gix-backup-<timestamp>/`.

---

## Common tasks

### See who is using what

```sh
squeue -o "%.8i %.12u %.10T %.10M %.12l %R"     # jobs, user, state, runtime, limit, node
sinfo -N -o "%N %T %G"                          # node state and GRES
scontrol show job <jobid>
```

### End a student's session

```sh
scancel -n devc-<netid>          # or: scancel <jobid>
```

All their processes and containers on the node are killed. Files stay.

### Take a node out / put it back

```sh
sudo scontrol update nodename=gix-30292620 state=drain reason="maintenance"   # running jobs finish, no new ones
sudo scontrol update nodename=gix-30292620 state=resume
```

A node stuck as `not responding` / `down` that is actually fine: `state=resume`.

### Add a GPU node

1. Install Slurm + munge (same `munge.key`), copy `/etc/slurm/*` from the controller.
2. Run the node scripts from `~/cluster-work/rollout/` (`node-all.sh` = Podman + CDI + PAM + prolog).
   Do PAM on **one node at a time** and test an admin login before closing your session.
3. Add a `NodeName=` line and the node to `PartitionName=gpu Nodes=` in `slurm.conf` on all hosts.
4. `sudo scontrol reconfigure`, `sudo systemctl restart slurmd` on the new node, check `sinfo`.

### NVIDIA driver update on a node

```sh
sudo scontrol update nodename=<node> state=drain reason="driver update"
# wait until no jobs run on it, update the driver, reboot
nvidia-smi                                     # driver loads?
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml   # normally done by nvidia-cdi-refresh
sudo scontrol update nodename=<node> state=resume
```

The kernel module must match the **running** kernel (`uname -r`). A node that boots a newer
kernel without matching NVIDIA modules has no `/dev/nvidia0` and Slurm marks it down.

### Free disk space (container images)

Each student's images live in `/var/lib/gix-containers/<netid>/` on each node they used (5–15 GB each).

```sh
sudo du -sh /var/lib/gix-containers/* | sort -h
sudo rm -rf /var/lib/gix-containers/<netid>     # only when that student has no job on this node
```

---

## Troubleshooting

### Students hang at login / "Access denied … by PAM account configuration" on the controller

Usually **SSSD** on the controller. Check:

```sh
time id <netid>                                   # should take < 1 s
journalctl -u sssd --since "-1h" | grep WATCHDOG  # crashes of the AD backend
```

If `id` hangs or there are watchdog kills:

```sh
sudo bash ~/cluster-work/rollout/fix-sssd-controller.sh cache    # reset the SSSD cache
sudo bash ~/cluster-work/rollout/fix-sssd-controller.sh config   # if it comes back
```

`config` sets `ad_enabled_domains = netid.washington.edu` and `ignore_group_members = True` in
`/etc/sssd/sssd.conf` (already applied on the controller). Both print a backup path and the rollback command.
Local accounts (admins, root) don't use SSSD and still work.

### Student: "job … still PENDING after 600s"

All shards are taken. `squeue` shows who has them. The student's job stays queued and starts when a slot frees up;
reconnecting picks it up.

### Student: asked for a password on the node / "Permission denied (publickey)"

The key copy to the node failed. Check that the job is running (`squeue -u <netid>`), then have the student
reconnect (keys are copied on every connect). On the node: `~<netid>/.ssh/authorized_keys` should contain their key.

### Student without a job: "Access denied by pam_slurm_adopt"

Expected: nodes only accept users who have a job there. Students connect through `gix-gpu`, never to a node directly.

### Podman: "invalid internal status … podman system migrate"

Stale runtime state from a killed job. The prolog clears it at the next job start; ending the job and reconnecting fixes it.

### Container has no GPU

```sh
nvidia-smi                          # on the node: driver OK?
ls /etc/cdi/nvidia.yaml             # CDI spec present?
podman run --rm --device=nvidia.com/gpu=all docker.io/nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi -L
```

The devcontainer must use `--device=nvidia.com/gpu=all` (CDI), not `--gpus`. RTX 5090 needs CUDA ≥ 12.8 images.

---

## Design decisions

- **Rootless Podman, no Docker daemon**: a Docker socket would give root on the node. `--privileged`,
  `--gpus`, `-v /dev:/dev` and `docker.sock` mounts are not supported.
- **No shared image store**: rootless Podman with a shared read-only store broke `apt-get` inside containers.
  Each student pulls into their own storage (a 4 GB PyTorch image takes about 3–4 minutes once per node).
- **Course-agnostic**: any project with a `.devcontainer/` works; nothing is specific to one class.
- **Not tied to the VS Code extension**: the server side only needs SSH. The optional extension
  ([gix-slurm-vscode-extension](https://github.com/alanyukeroo/gix-slurm-vscode-extension)) adds a sign-in button,
  queue status and a release button.
