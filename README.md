# ODSC West 2026 Workshop: Geo-Enabled Entity Resolved Knowledge Graphs for GraphRAG
### Clair J. Sullivan, PhD
### clair@clairsullivan.com
#### Last modified: October 23, 2026

Workshop materials for building a geo-enabled, entity-resolved knowledge graph (ERKG) and using it to answer questions a conventional RAG pipeline cannot. The workshop resolves 39,413 records from eight California public-records sources into 31,339 real businesses (entities) using Senzing, geocodes them with Placekey, assembles the result as a NetworkX graph, and compares LLM answers with and without that structure. Also uses LanceDB for vector storage, FastEmbed for embeddings, Folium for mapping, and either Anthropic Claude or OpenAI for the question answering.

## Requirements

- Docker Desktop (macOS/Windows) or Docker Engine + Compose (Linux)
- ~10 GB free disk space, and a ~2.5 GB download
- API key for [Anthropic](https://platform.claude.com/) and/or [OpenAI](https://platform.openai.com/)
- PowerShell (Windows users only)
- NO Senzing license needed. The database ships already resolved, and reading a resolved database is unlimited.

## BEFORE YOU BEGIN

**Pull the container images before the workshop.** 

```
docker pull ghcr.io/cj2001/erkg-jupyter:west-2026 ; docker pull ghcr.io/cj2001/erkg-db:west-2026 ; docker pull senzing/serve-grpc:latest
```

Then follow the instructions in **[SETUP.md](SETUP.md)**.

## Data Sources

All eight sources are California public records, obtained directly from the issuing agency. The copies in `data/filtered/` have been narrowed to the San Francisco Peninsula so that the workshop runs in a reasonable time and inside the Placekey free tier.

| Source | Records | Entities | Where it came from |
| --- | --- | --- | --- |
| `CA-CONTRACTOR-PERSONNEL` | 10,215 | 9,457 | Officers and managing employees attached to contractor licenses, from the [CSLB data portal](https://www2.cslb.ca.gov/onlineservices/dataportal/) |
| `CA-SOS-FILINGS` | 7,801 | 7,730 | Registered businesses, from [CA Secretary of State bizfile Online](https://bizfileonline.sos.ca.gov/) |
| `CA-SOS-AGENTS` | 7,421 | 4,958 | Registered agents, from [CA Secretary of State bizfile Online](https://bizfileonline.sos.ca.gov/) |
| `CA-SOS-PRINCIPALS` | 5,701 | 3,306 | Corporate officers and LLC managers, from [CA Secretary of State bizfile Online](https://bizfileonline.sos.ca.gov/) |
| `BURLINGAME` | 4,781 | 4,751 | City of Burlingame business registrations, from [burlingame.hdlgov.com](https://burlingame.hdlgov.com/) |
| `CA-CONTRACTORS` | 3,274 | 3,186 | Licensed contractors, from the [CSLB data portal](https://www2.cslb.ca.gov/onlineservices/dataportal/) |
| `ABC-RETAIL` | 201 | 173 | Retail liquor licenses, by [public records request to CA ABC](https://www.abc.ca.gov/contact/public-records-request/) |
| `ABC-NONRETAIL` | 19 | 14 | Non-retail liquor licenses, by [public records request to CA ABC](https://www.abc.ca.gov/contact/public-records-request/) |
| **Total** | **39,413** | **31,339** | compression 1.26 |

Geographic coordinates come from [Placekey](https://www.placekey.io/), which returns a `what@where` identifier whose `where` half is an H3 resolution-10 hexagon. 

Note that the full statewide source files are not in this repository. `data/filtered/` holds the narrowed copies the notebooks actually read.

## File Descriptions

### Setup & Infrastructure

- **[SETUP.md](SETUP.md)**: Step-by-step instructions for getting the workshop environment running: installing Docker, pulling the images, cloning the repo, adding an API key, starting the stack, and verifying everything works. Also includes troubleshooting for the problems people actually hit.

- **[docker-compose.yml](docker-compose.yml)**: Defines the four-container stack: PostgreSQL 15 holding the resolved data, a Senzing gRPC server as the resolution engine, a second Senzing gRPC server serving an empty "sandbox" repository that attendees can load into with a free license, and JupyterLab.

- **[Dockerfile](Dockerfile)**: Builds the JupyterLab container from `jupyter/base-notebook`, adding `senzing-grpc`, `psycopg2-binary`, `placekey`, `lancedb`, `pandas`, `sqlalchemy`, `networkx`, `folium`, `fastembed`, `anthropic`, and `openai`. The `all-MiniLM-L6-v2` embedding model is baked in so nobody downloads it on conference wifi.

- **[docker/postgres/](docker/postgres/)**: Builds the pre-loaded database image. Carries the resolved `erkg` dump and the empty `sandbox` dump, with a script that restores both on first boot. This is what removes the need for attendees to have a Senzing license.

- **[scripts/start.sh](scripts/start.sh)** and **[scripts/start.ps1](scripts/start.ps1)**: Bring up the stack safely. Create `.env` if missing, record your user and group id so files written into `./notebooks` belong to you, create the bind-mount directories before Docker can create them as root, pull the published images, and wait for the health checks.

- **[scripts/init_database.sh](scripts/init_database.sh)** and **[scripts/init_database.ps1](scripts/init_database.ps1)**: Initialize the Senzing schema if it is not already there. Safe to re-run; detects an initialized database and returns.

### Notebooks

Run these in order. Notebook `01` is optional and is the only one that needs a Senzing license.

- **[00_test_setup.ipynb](notebooks/00_test_setup.ipynb)**: Verifies the environment: PostgreSQL connectivity, both Senzing gRPC servers, license validity, LanceDB, NetworkX, Folium, and every Python package. Then walks through the Senzing SDK end to end in the sandbox repository: registering a data source, loading four records, watching two of them resolve into one entity while a third stays separate and a person at the same address is deliberately not merged, and asking `why_entities` to explain the decision.

- **[01_OPT_populate_db.ipynb](notebooks/01_OPT_populate_db.ipynb)**: **Optional, and not run during the workshop.** Shows how the shipped database was built: mapping all eight sources into the Senzing entity specification, loading 39,413 records, geocoding the local addresses with the Placekey API, and building the `workshop.geo_address` and `workshop.entity_geo` tables that join coordinates to resolved entities. Requires a Senzing license covering 39,413 records, which the free tier does not.

- **[02_eda.ipynb](notebooks/02_eda.ipynb)**: Explores the raw data and what resolution made of it. Looks at the published columns, shows why exact-match deduplication fails, inspects the tables Senzing built, and then works through the SDK: one entity assembled from several records, the features behind it, `how_entity_by_entity_id` replaying each merge step, `search_by_attributes`, related-but-not-merged entities, and `why_entities` on a pair Senzing deliberately refused to merge.

- **[03_graph_viz.ipynb](notebooks/03_graph_viz.ipynb)**: Puts the resolution results on a map with Folium. One marker per Placekey cell sized by how many businesses are there, shaped by which datasets they appear in, colored to pick out liquor licenses, with Senzing relationships drawn as styled edges and a search box to fly to any entity. Ends with an exercise: a cluster of markers sitting in a park, and what that reveals about silent geocoding failure.

- **[04_rag_without_erkg.ipynb](notebooks/04_rag_without_erkg.ipynb)**: Conventional RAG over the raw rows, with no entity resolution and no coordinates. Embeds 8,275 published records with FastEmbed into LanceDB and asks an LLM about them. The answers are fluent, specific, and wrong in instructive ways. This is the baseline the next notebook is measured against.

- **[05_geoerkg.ipynb](notebooks/05_geoerkg.ipynb)**: The geo-enabled ERKG. Builds a NetworkX graph of all 31,339 resolved entities with Placekey coordinates as node properties and Senzing match keys as edges, then answers questions by resolving the question to a starting entity with `search_by_attributes`, walking the graph outward from there, computing real distances, and handing the result to an LLM. Asks the same questions as notebook 04 so the difference is directly visible.

## Useful Resources

- [Senzing Documentation](https://senzing.com/docs/)
- [Placekey documentation](https://docs.placekey.io/)
- [H3 geospatial indexing](https://h3geo.org/)
