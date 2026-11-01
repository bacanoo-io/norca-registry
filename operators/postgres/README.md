<!--
SPDX-FileCopyrightText: 2026 Norca contributors
SPDX-License-Identifier: MPL-2.0
-->

# PostgreSQL operator

An operator of the [dynamic secrets](https://github.com/bacanoo-io/norca-doc/blob/main/content/docs/features/secrets/dynamic.md)
of Norca: it creates a PostgreSQL login role for each lease, and drops it when the
lease is revoked. It is a separate program that runs as a job. Norca only knows the
service name in the engine, so you can replace it with your own.

No pack and no image are published: build the binary and adapt
[`postgres-operator.nomad.hcl`](postgres-operator.nomad.hcl) and [`engine.hcl`](engine.hcl).

## Build

Norca has no released modules yet, so `go.mod` takes the SDK from a checkout of the
Norca repository next to this one:

```shell
git clone https://github.com/bacanoo-io/norca
git clone https://github.com/bacanoo-io/norca-registry
cd norca-registry/operators/postgres
CGO_ENABLED=0 go build -o postgres-operator .
```

## Set up PostgreSQL

The admin role needs `CREATEROLE`, not superuser, and `ADMIN OPTION` on the group
roles. Rights come from those groups, so the engine holds no SQL:

```sql
CREATE ROLE norca_operator LOGIN CREATEROLE PASSWORD '...';
CREATE ROLE orders_rw NOLOGIN;
GRANT orders_rw TO norca_operator WITH ADMIN OPTION;
GRANT CONNECT ON DATABASE orders TO orders_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO orders_rw;
```

The operator serves one server, reached with the standard variables `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, `PGPASSWORD` and `PGSSLMODE`.

Rotate the password of the admin role, but keep the role: from PostgreSQL 16 only the
role that created a credential can drop it. After a change of `PGUSER` the drops of the
older credentials fail and are logged, until a superuser removes them.

## Flags

| Flag | Default | |
| --- | --- | --- |
| `-addr` | `:$NOMAD_PORT_api` | The address to listen on. |
| `-role-prefix` | `v_` | Starts the names of the roles, followed by the lease ID. Roles without it are never changed or dropped. Two operators of a server need different prefixes. Changing it leaves the existing roles without an owner. |
| `-sweep-interval` | `5m` | How often expired roles are looked for. `0` turns the sweep off. |
| `-sweep-grace` | `1h` | How long a role stays after its `VALID UNTIL`. |

## Role config

| Key | |
| --- | --- |
| `member_of` | The group roles of the credential, comma-separated. Required; an unknown group refuses the request. |
| `database` | The database delivered to the task; by default `PGDATABASE`. |
| `host`, `port` | The address delivered to the task; by default that of `PGHOST`. |
| `sslmode` | Added to the `uri` item. |

A task gets the items `username`, `password`, `host`, `port`, `database` and `uri`.

## Tests

The tests that need a server run with a superuser URL and drop every role that looks
like one of the operator's, so use a throwaway server:

```shell
POSTGRES_TEST_URL='postgres://postgres:root@127.0.0.1:5432/postgres?sslmode=disable' go test ./...
```
