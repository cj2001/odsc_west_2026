# Workshop Setup

Everything runs in Docker. You do not need Python, PostgreSQL, or a Senzing
licence on your machine — only Docker and a text editor.

Budget about 15 minutes, most of it downloading images. **Do this before the
workshop, on the network you trust, not on conference wifi.**

---

## What you need

- **Docker Desktop** (macOS / Windows) or **Docker Engine + Compose** (Linux)
- **~15 GB free disk space** for the images
- **An LLM API key** — Anthropic or OpenAI — for the final notebook only
- **No Senzing licence.** The workshop database arrives already loaded and
  entity-resolved. Reading a resolved database is unlimited; only *loading* new
  records needs a licence, and you will not be loading any.

---

## 1. Install Docker

**macOS / Windows** — install [Docker Desktop](https://www.docker.com/products/docker-desktop/),
launch it, and wait for the whale icon to stop animating.

**Linux** — install Docker Engine and the Compose plugin from
[docs.docker.com/engine/install](https://docs.docker.com/engine/install/), then
add yourself to the `docker` group so you do not need `sudo`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Check it works:

```bash
docker run --rm hello-world
```

## 2. Clone the repository

```bash
git clone https://github.com/cj2001/odsc_west_2026.git
cd odsc_west_2026
```

## 3. Add your LLM key

Copy the template and open it in a text editor:

```bash
cp .env.example .env
```

Set **one** of these:

```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

Leave everything else alone. The other keys are optional and are only needed if
you want to rebuild the workshop data yourself later. `.env` is git-ignored, so
your key stays on your machine.

## 4. Start everything

**macOS / Linux**

```bash
./scripts/start.sh
```

**Windows (PowerShell)**

```powershell
.\scripts\start.ps1
```

The script pulls the images, creates the directories Docker needs, starts the
four containers, waits for them to report healthy, and checks the database.

The first run downloads several GB and will take a while. Later runs take
seconds. When it finishes you will see:

```
============================================
✅ READY
============================================
Open JupyterLab: http://localhost:18888
```

## 5. Verify

Open <http://localhost:18888> — no password or token — and run
**`notebooks/00_test_setup.ipynb`** top to bottom. Every cell should print ✅.

That notebook checks the database connection, the resolver connection, and the
Python packages. If it is all green, you are ready.

---

## What is running

| Service | Container | URL / port | What it does |
| --- | --- | --- | --- |
| JupyterLab | `erkg_jupyter` | <http://localhost:18888> | where you work |
| PostgreSQL | `erkg_postgres` | `localhost:5436` | the resolved data |
| Resolver | `erkg_resolver` | `localhost:8261` | entity resolution engine (gRPC) |
| Portainer | `erkg_portainer` | <http://localhost:9000> | optional container UI |

Your `notebooks/` and `data/` folders are shared with the container, so edits
you make in JupyterLab appear on your own disk and survive restarts.

---

## If something goes wrong

**"port is already allocated"** — something else is using 18888, 5436, 8261,
9000, or 9443. Stop it, or change the left-hand number of the matching
`ports:` entry in `docker-compose.yml` (for example `18889:8888`) and re-run
the start script.

**JupyterLab will not open** — give it another 30 seconds on the first run, then
check the containers are up:

```bash
docker ps --filter name=erkg_
```

All four should say `Up`, and three should say `(healthy)`.

**Permission errors writing notebooks (Linux only)** — re-run
`./scripts/start.sh`. It detects and repairs directory ownership. This happens
when Docker creates a missing folder as `root` before you first start the stack.

**The pull is slow or fails** — re-run the start script; Docker resumes
partially downloaded layers rather than starting over.

**Start fresh without losing the data:**

```bash
docker compose down
./scripts/start.sh
```

> **Do not run `docker compose down -v`.** The `-v` deletes the volume holding
> the pre-loaded, entity-resolved database, and rebuilding it needs a Senzing
> licence you do not have. Plain `down` stops the containers and keeps your data.

---

## When you are finished

Stop the stack but keep everything:

```bash
docker compose down
```

Remove the images too, once the workshop is over and you want the disk back:

```bash
docker compose down
docker rmi ghcr.io/cj2001/erkg-jupyter:west-2026
```
