// SPDX-FileCopyrightText: 2026 Norca contributors
// SPDX-License-Identifier: MPL-2.0

// Command postgresoperator is an operator of the dynamic secrets of Norca: it
// creates a PostgreSQL login role for each lease, and drops it when the lease
// is revoked.
//
// It serves one PostgreSQL server, reached with the standard PG* environment
// variables (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD, PGSSLMODE). The
// admin role needs CREATEROLE, and ADMIN OPTION on the group roles:
//
//	CREATE ROLE norca_operator LOGIN CREATEROLE PASSWORD '...';
//	CREATE ROLE orders_rw NOLOGIN;
//	GRANT orders_rw TO norca_operator WITH ADMIN OPTION;
//	GRANT CONNECT ON DATABASE orders TO orders_rw;
//	GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO orders_rw;
//
// Rights come from those group roles, so no SQL is kept in the engine. The
// role config of the engine holds:
//
//	member_of  the group roles of the credential, comma-separated (required)
//	database   the database delivered to the task; by default PGDATABASE
//	host, port the address delivered to the task; by default that of PGHOST
//	sslmode    added to the uri item
//
// A task gets the items username, password, host, port, database and uri.
//
// The flags -role-prefix, -sweep-interval and -sweep-grace are described in the
// README.
//
// The operator keeps no state: the name of a role comes from its lease ID, and
// VALID UNTIL follows the lease. If the operator is down, password logins stop
// when the lease ends, and a sweep removes the role later. Tables a credential
// created stay with the admin role when it is dropped.
//
// It prints what happens to standard error, without the passwords:
//
//	issued lease=<id> ref=<role> task=<job>/<group>/<task>
//	revoked ref=<role>
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/bacanoo-io/norca/norca/controller/secrets"
	"github.com/jackc/pgx/v5/pgxpool"
)

// options are the settings of the flags.
type options struct {
	addr          string
	prefix        string
	sweepInterval time.Duration
	sweepGrace    time.Duration
}

func (o *options) check() error {
	if err := checkPrefix(o.prefix); err != nil {
		return err
	}
	if o.sweepInterval < 0 || o.sweepGrace < 0 {
		return errors.New("-sweep-interval and -sweep-grace can't be negative")
	}
	return nil
}

func run(ctx context.Context, o *options) error {
	if err := o.check(); err != nil {
		return err
	}
	config, err := pgxpool.ParseConfig("")
	if err != nil {
		return fmt.Errorf("reading the PG* environment: %w", err)
	}
	// No connection is made here: PostgreSQL may start after the operator,
	// and until then the requests fail like an outage.
	db, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return err
	}
	defer db.Close()

	b := newBackend(db, config.ConnConfig, o.prefix, o.sweepGrace)
	if o.sweepInterval > 0 {
		go func() {
			ticker := time.NewTicker(o.sweepInterval)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					if err := b.sweep(ctx); err != nil {
						log.Printf("sweep: %v", err)
					}
				}
			}
		}()
	}
	return secrets.Serve(ctx, o.addr, secrets.TLSFromEnv(), b)
}

func main() {
	o := &options{}
	flag.StringVar(&o.addr, "addr", ":"+os.Getenv("NORCA_PORT_api"), "address to listen on")
	flag.StringVar(&o.prefix, "role-prefix", "v_", "start of the names of the roles; nothing else is ever changed or dropped")
	flag.DurationVar(&o.sweepInterval, "sweep-interval", 5*time.Minute, "how often expired roles are looked for; 0 turns the sweep off")
	flag.DurationVar(&o.sweepGrace, "sweep-grace", time.Hour, "how long a role stays after its VALID UNTIL")
	flag.Parse()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, o); err != nil {
		log.Fatal(err)
	}
}
