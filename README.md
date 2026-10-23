# How to access the GIX GPU cluster

Run your code on an **NVIDIA RTX 5090** from VS Code on your own laptop.
You open a project as usual, and it runs in a container on a GPU node of the GIX cluster.

```
your laptop (VS Code) ──► gix-login ──► Slurm gives you a GPU ──► your dev container
```

## Before you start

- A **UW NetID**
- You are on the **UW network** (on campus, or off campus with **Husky OnNet** VPN)
- **VS Code** with two extensions from Microsoft:
  - **Remote - SSH**
  - **Dev Containers**

> Windows is not supported yet. macOS and Linux only for now.

---

## Step 1: Set up your laptop (one time only)

Open **Terminal** and run:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/alanyukeroo/how-to-access-gix-cluster/main/setup/gix-setup.sh)"
```

- Type your **NetID** when asked.
- If it asks for a passphrase for a new SSH key, press **Enter** twice.
- At the end, type your **NetID password** (this is the only time).

## Step 2: Test it

In Terminal:

```sh
ssh gix-gpu hostname
```

You should see something like:

```
[gix-devjob] no dev job running, requesting one (gres=shard:1 cpus=4 mem=12G time=04:00:00)
[gix-devjob] connected to gix-30292585 (job 137; ends after 30 idle minutes or at 04:00:00)
gix-30292585
```

No password prompt = everything works.

---

## Every time you want to work

1. In VS Code: `Cmd+Shift+P` → **Remote-SSH: Connect to Host…** → **gix-gpu**
   (choose **Linux** if asked)
2. **File → Open Folder…** → your project folder
3. Click **Reopen in Container** (or `Cmd+Shift+P` → **Dev Containers: Reopen in Container**)

That's it. The bottom-left corner shows **Dev Container: …** when you are in.

### First time: create a project from the template

Once you are connected to **gix-gpu**, open a terminal in VS Code (`` Ctrl+` ``) and run:

```sh
git clone https://github.com/alanyukeroo/how-to-access-gix-cluster.git ~/gix-template
cp -r ~/gix-template/template ~/my-project
```

Then **Open Folder** → `~/my-project` → **Reopen in Container**.
The first build downloads PyTorch (a few minutes); after that it starts in seconds.

Check the GPU in the container terminal:

```sh
python gpu_check.py
```

```
CUDA available: True
device: NVIDIA GeForce RTX 5090
```

---

## Good to know

| | |
|---|---|
| **GPU size** | You get a quarter of an RTX 5090 (`shard:1`) by default |
| **Time limit** | 4 hours per session |
| **Closing VS Code** | Your GPU is released automatically after **30 minutes** without a connection |
| **Your files** | They are saved on the GPU node you used. You might get a different node next time, so **keep your code in git** (push often) |

## Troubleshooting

| Problem | Fix |
|---|---|
| `ssh gix-gpu` hangs or times out | Are you on the UW network or Husky OnNet? |
| It asks for a password every time | Run Step 1 again |
| `[gix-devjob] job … is PENDING, waiting...` for a long time | All GPUs are busy. Wait, or try again later |
| VS Code says "Could not establish connection" while the cluster is busy | VS Code gives up after 15 s, but getting a GPU can take longer. `Cmd+Shift+P` → **Preferences: Open User Settings (JSON)**, add `"remote.SSH.connectTimeout": 660,` inside the `{ }`, save, and connect again |
| Terminal in the container has no Tab completion | Use the template's `devcontainer.json` (it sets the terminal to `bash`), then **Dev Containers: Rebuild Container** |

Still stuck? Send your TA the output of `ssh -v gix-gpu hostname`.
