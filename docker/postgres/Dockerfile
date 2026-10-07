# The pre-loaded workshop database.
#
# Attendees cannot build this database themselves: it holds 39,413 records and a
# free Senzing licence caps loading at 500. Reading an already-resolved database
# is unlimited, so shipping it this way removes the licence from their setup
# entirely.
#
# Stock Postgres runs anything in /docker-entrypoint-initdb.d exactly once, the
# first time it starts with an empty data directory. So the dump restores on
# first boot with no custom entrypoint and nothing for attendees to download.
FROM postgres:15

COPY erkg.dump /opt/erkg/erkg.dump

# A second, EMPTY Senzing repository. The free 500-record licence counts records
# already in the repository, so attendees cannot add even one record to the
# 39,413-record main database. This gives them somewhere the load/resolve code
# genuinely runs.
COPY sandbox.dump /opt/erkg/sandbox.dump
COPY 10-restore-erkg.sh /docker-entrypoint-initdb.d/10-restore-erkg.sh
