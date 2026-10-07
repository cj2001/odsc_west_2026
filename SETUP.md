# Workshop Setup

Everything runs in Docker. You do not need Python, PostgreSQL, or a Senzing
licence on your machine — only Docker and a text editor.

**Do the download step before the workshop, on a network you trust. Not on
conference wifi.** It is about 2.5 GB.

---

## What you need

- **Docker Desktop** (macOS / Windows) or **Docker Engine + Compose** (Linux)
- **~10 GB free disk space**
- **An LLM API key** — Anthropic or OpenAI — for the last two notebooks only
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

## 2. Download the images — do this early

One line. No clone needed, nothing to configure. Works the same on Mac, PC and
Linux, and Docker picks the right build for your processor automatically:

```
docker pull ghcr.io/cj2001/erkg-jupyter:west-2026 ; docker pull ghcr.io/cj2001/erkg-db:west-2026 ; docker pull senzing/serve-grpc:latest
```

> Use `;` between the commands, not `&&`. Windows PowerShell does not support
> `&&`, and `;` works everywhere.

About 2.5 GB. It is resumable — if your connection drops, run the same line
again and Docker continues from where it stopped.

Check all three arrived:

```
docker image ls --filter reference=*erkg* --filter reference=*serve-grpc*
```

## 3. Clone the repository

```bash
git clone --depth 1 https://github.com/cj2001/odsc_west_2026.git
cd odsc_west_2026
```

`--depth 1` skips the project history and downloads about 10 MB instead of
50 MB. You do not need the history for the workshop.

## 4. Add your LLM key

Copy the template and open `.env` in a text editor:

```bash
cp .env.example .env
```

Set **one** of these:

```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

Leave everything else alone. The other keys are optional and only needed if you
want to rebuild the workshop data yourself later. `.env` is git-ignored, so your
key stays on your machine.

> `.env` must exist before you start the stack — Docker Compose reads it and
> will refuse to start without it. Copying the template is enough; the keys can
> be blank until you reach the final notebooks.

## 5. Start everything

**macOS / Linux**

```bash
./scripts/start.sh
```

**Windows (PowerShell)**

```powershell
.\scripts\start.ps1
```

The script creates the directories Docker needs, starts the three containers,
waits for them to report healthy, and checks the database. Because you already
pulled the images in step 2, this takes under a minute.

When it finishes you will see:

```
============================================
✅ READY
============================================
Open JupyterLab: http://localhost:18888
```

## 6. Verify

Open <http://localhost:18888> — no password or token — and run
**`notebooks/00_test_setup.ipynb`** top to bottom. Every cell should print ✅.

That notebook checks the database connection, the resolver connection, and the
Python packages. If it is all green, you are ready.

---

## What is running

| Service | Container | Port | What it does |
| --- | --- | --- | --- |
| JupyterLab | `erkg_jupyter` | <http://localhost:18888> | where you work |
| PostgreSQL | `erkg_postgres` | `localhost:5436` | the resolved data |
| Resolver | `erkg_resolver` | `localhost:8261` | entity resolution engine (gRPC) |
| Sandbox | `erkg_sandbox` | `localhost:8262` | empty repository you can load into |

The resolver and the sandbox share one image, so they are a single download.
The sandbox is a second, empty Senzing repository — you can add records to it
with a free licence and watch resolution happen, without touching the workshop
database.

Your `notebooks/` and `data/` folders are shared with the container, so edits
you make in JupyterLab appear on your own disk and survive restarts.

---

## If something goes wrong

**"env file .env not found"** — you skipped step 4. `cp .env.example .env`.

**"port is already allocated"** — something else is using 18888, 5436, 8261 or
8262. Stop it, or change the left-hand number of the matching `ports:` entry in
`docker-compose.yml` (for example `18889:8888`) and re-run the start script.

**JupyterLab will not open** — give it another 30 seconds, then check the
containers:

```bash
docker ps --filter name=erkg_
```

All three should say `Up`, and all three should say `(healthy)`.

**Permission errors writing notebooks (Linux only)** — re-run
`./scripts/start.sh`. It detects and repairs directory ownership. This happens
when Docker creates a missing folder as `root` before you first start the stack.

**A cell hangs with no output** — the notebooks that call an LLM need a key in
`.env`. If you edited `.env` after starting, the running container has not seen
it; `docker compose up -d` recreates the container with the new values.

**Start fresh without losing the data:**

```bash
docker compose down
./scripts/start.sh
```

> **Avoid `docker compose down -v` during the workshop.** The `-v` deletes the
> volume holding the database. It is recoverable — the dump ships inside the
> image, so the next `up` restores it automatically and needs no licence — but
> the restore takes a minute or two, and anything you loaded into the sandbox
> yourself is gone. Plain `down` stops the containers and keeps everything.

---

## When you are finished

Stop the stack but keep everything:

```bash
docker compose down
```

Reclaim the disk once the workshop is over:

```bash
docker compose down -v
docker rmi ghcr.io/cj2001/erkg-jupyter:west-2026 ghcr.io/cj2001/erkg-db:west-2026 senzing/serve-grpc:latest
```

---

## Presenter notes

*Not part of the attendee setup — notes for running this live.*

**Steps 2–4 are already done on your machine.** You have all three images and a
working `.env`. Start at step 5. If you want to rehearse the attendee
experience, do it in a fresh clone in another directory rather than resetting
this one.

**Run `./scripts/start.sh` anyway**, because it is what you are telling the room
to run. On your machine it changes nothing: your uid is 1000, which is already
the template default, and the database is already initialised so
`init_database.sh` returns immediately. It is idempotent, so running it mid-talk
is safe.

**Your `.env` holds a real Senzing licence, commented out.** Leave it commented.
With it active your resolver can load records that an attendee's cannot, so the
sandbox exercise would behave differently for you than for the room.

**If you need to reset the database live**, `docker compose down -v` followed by
`./scripts/start.sh` restores it from the dump inside the image in a minute or
two. No licence needed. You lose anything loaded into the sandbox.

**Do not run `docker compose build`.** The jupyter service has both `image:` and
`build:`, so building tags the result as `ghcr.io/cj2001/erkg-jupyter:west-2026`
and overwrites your local copy of the published image. Use `docker build -t`
with a different tag if you need to try a change.

**Before the conference:** rebuild from the pinned base digest, run every
notebook from a cold kernel, and re-verify the arm64 image. The package set is
pip-pinned rather than conda-managed, so a dependency can shift under a rebuild
— that is how pandas 3.0 broke `pd.read_sql` once already.
