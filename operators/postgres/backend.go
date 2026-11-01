// SPDX-FileCopyrightText: 2026 Norca contributors
// SPDX-License-Identifier: MPL-2.0

package main

import (
	"context"
	"crypto/hmac"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/bacanoo-io/norca/nomad/controller/secrets"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// scramIterations is the default of PostgreSQL.
	scramIterations = 4096

	// PostgreSQL error codes.
	duplicateObject = "42710"
	undefinedObject = "42704"
)

// validPrefix bounds a role prefix: with the 32 digits of the lease ID the name
// must fit into the 63 bytes of PostgreSQL.
var validPrefix = regexp.MustCompile(`^[a-z_][a-z0-9_]{0,30}$`)

// checkPrefix refuses a prefix that can't start the name of a role.
func checkPrefix(prefix string) error {
	if !validPrefix.MatchString(prefix) {
		return fmt.Errorf("role prefix %q: 1 to 31 lower case letters, digits and underscores, not starting with a digit", prefix)
	}
	if strings.HasPrefix(prefix, "pg_") {
		return fmt.Errorf("role prefix %q: pg_ is reserved by PostgreSQL", prefix)
	}
	return nil
}

// backend creates login roles in one PostgreSQL server.
type backend struct {
	db *pgxpool.Pool

	// prefix starts the name of every role of the operator, and managed
	// matches them. Nothing else is ever changed or dropped.
	prefix  string
	managed *regexp.Regexp

	// grace is how long a role stays after its VALID UNTIL. A lease can't
	// be renewed while the leader is away, which must not cost the open
	// connections of the task.
	grace time.Duration

	// The address and database delivered to the tasks, unless the role
	// config names others.
	host     string
	port     string
	database string
}

func newBackend(db *pgxpool.Pool, config *pgx.ConnConfig, prefix string, grace time.Duration) *backend {
	return &backend{db: db, prefix: prefix, grace: grace,
		managed: regexp.MustCompile(`^` + regexp.QuoteMeta(prefix) + `[0-9a-f]{32}$`),
		host:    config.Host, port: fmt.Sprint(config.Port), database: config.Database}
}

// roleOf returns the role of a lease ID or of a reference, which is the lease
// ID if an issue did not finish; "" for anything else, such as a role that
// doesn't belong to the operator.
func (b *backend) roleOf(ref string) string {
	if b.managed.MatchString(ref) {
		return ref
	}
	if role := b.prefix + strings.ReplaceAll(ref, "-", ""); b.managed.MatchString(role) {
		return role
	}
	return ""
}

// scramVerifier hashes a password here, so that the statement that creates the
// role can't leave it in the logs of the server or in pg_stat_activity.
func scramVerifier(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	salted, err := pbkdf2.Key(sha256.New, password, salt, scramIterations, sha256.Size)
	if err != nil {
		return "", err
	}
	mac := func(message string) []byte {
		h := hmac.New(sha256.New, salted)
		h.Write([]byte(message))
		return h.Sum(nil)
	}
	stored := sha256.Sum256(mac("Client Key"))
	b64 := base64.StdEncoding.EncodeToString
	return fmt.Sprintf("SCRAM-SHA-256$%d:%s$%s:%s", scramIterations, b64(salt), b64(stored[:]), b64(mac("Server Key"))), nil
}

// roleList quotes the names of a comma-separated list.
func roleList(list string) string {
	var names []string
	for _, name := range strings.Split(list, ",") {
		if name = strings.TrimSpace(name); name != "" {
			names = append(names, pgx.Identifier{name}.Sanitize())
		}
	}
	return strings.Join(names, ", ")
}

// validUntil is the VALID UNTIL clause of a credential: password logins stop
// when the lease ends, also if the revocation doesn't reach the operator.
func validUntil(ttl time.Duration) string {
	return "VALID UNTIL '" + time.Now().Add(ttl).UTC().Format(time.RFC3339) + "'"
}

// Issue creates a role for the lease. A repeated call finds the role and gives
// it a new password, since the first answer was lost.
func (b *backend) Issue(ctx context.Context, req *secrets.IssueRequest) (*secrets.Credential, error) {
	role := b.roleOf(req.LeaseID)
	if role == "" {
		return nil, &secrets.Invalid{Reason: "the lease ID is not a UUID"}
	}
	groups := roleList(req.Config["member_of"])
	if groups == "" {
		return nil, &secrets.Invalid{Reason: "the role config needs member_of"}
	}
	random := make([]byte, 24)
	if _, err := rand.Read(random); err != nil {
		return nil, err
	}
	password := hex.EncodeToString(random)
	verifier, err := scramVerifier(password)
	if err != nil {
		return nil, err
	}

	name := pgx.Identifier{role}.Sanitize()
	attrs := fmt.Sprintf("PASSWORD '%s' %s", verifier, validUntil(req.TTL))
	_, err = b.db.Exec(ctx, fmt.Sprintf("CREATE ROLE %s LOGIN INHERIT %s IN ROLE %s", name, attrs, groups))
	var pgErr *pgconn.PgError
	switch {
	case errors.As(err, &pgErr) && pgErr.Code == undefinedObject:
		return nil, &secrets.Invalid{Reason: pgErr.Message}
	case errors.As(err, &pgErr) && pgErr.Code == duplicateObject:
		_, err = b.db.Exec(ctx, fmt.Sprintf("ALTER ROLE %s %s", name, attrs))
	}
	if err != nil {
		return nil, fmt.Errorf("creating the role: %w", err)
	}
	log.Printf("issued lease=%s ref=%s task=%s/%s/%s", req.LeaseID, role, req.JobID, req.TaskGroup, req.Task)
	return &secrets.Credential{Items: b.items(req.Config, role, password), Ref: role}, nil
}

// items builds what a task gets. Each item can be mapped on its own, and the
// uri covers clients that take one string.
func (b *backend) items(config map[string]string, role, password string) map[string]string {
	pick := func(key, fallback string) string {
		if v := config[key]; v != "" {
			return v
		}
		return fallback
	}
	host, port, database := pick("host", b.host), pick("port", b.port), pick("database", b.database)
	uri := url.URL{Scheme: "postgres", User: url.UserPassword(role, password),
		Host: net.JoinHostPort(host, port), Path: "/" + database}
	if mode := config["sslmode"]; mode != "" {
		uri.RawQuery = url.Values{"sslmode": {mode}}.Encode()
	}
	return map[string]string{"username": role, "password": password, "host": host, "port": port,
		"database": database, "uri": uri.String()}
}

// Renew moves the VALID UNTIL of the role. A role that is gone fails the
// renewal: the task gets a new credential when its lease ends.
func (b *backend) Renew(ctx context.Context, req *secrets.RenewRequest) (*secrets.Renewal, error) {
	role := b.roleOf(req.Ref)
	if role == "" {
		return nil, &secrets.Invalid{Reason: "not a role of this operator"}
	}
	stmt := fmt.Sprintf("ALTER ROLE %s %s", pgx.Identifier{role}.Sanitize(), validUntil(req.TTL))
	if _, err := b.db.Exec(ctx, stmt); err != nil {
		return nil, fmt.Errorf("renewing the role: %w", err)
	}
	return &secrets.Renewal{}, nil
}

// Revoke drops the roles of the list that still exist. The list comes again
// until it is empty, so a failure of one role doesn't stop the others.
func (b *backend) Revoke(ctx context.Context, req *secrets.RevokeRequest) error {
	var roles []string
	for ref := range req.Revoked {
		if role := b.roleOf(ref); role != "" {
			roles = append(roles, role)
		}
	}
	rows, err := b.db.Query(ctx, "SELECT rolname FROM pg_roles WHERE rolname = ANY($1)", roles)
	if err != nil {
		return fmt.Errorf("listing the roles: %w", err)
	}
	existing, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return fmt.Errorf("listing the roles: %w", err)
	}
	return b.drop(ctx, existing)
}

// sweep drops the roles the leader no longer lists: it stops listing a
// revocation when the credential expires, which an operator that was down
// never saw.
func (b *backend) sweep(ctx context.Context) error {
	rows, err := b.db.Query(ctx, "SELECT rolname FROM pg_roles WHERE rolname ~ $1 AND rolvaliduntil < $2",
		b.managed.String(), time.Now().Add(-b.grace))
	if err != nil {
		return fmt.Errorf("listing the expired roles: %w", err)
	}
	expired, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return fmt.Errorf("listing the expired roles: %w", err)
	}
	return b.drop(ctx, expired)
}

func (b *backend) drop(ctx context.Context, roles []string) error {
	var errs []error
	for _, role := range roles {
		if err := b.dropRole(ctx, role); err != nil {
			errs = append(errs, fmt.Errorf("dropping %s: %w", role, err))
			continue
		}
		log.Printf("revoked ref=%s", role)
	}
	return errors.Join(errs...)
}

// dropRole ends a role: no new logins, no open connections, and what it created
// stays with the admin. The GRANT gives the admin the membership these steps
// need when it has CREATEROLE but isn't a superuser.
func (b *backend) dropRole(ctx context.Context, role string) error {
	name := pgx.Identifier{role}.Sanitize()
	for _, stmt := range []string{
		"ALTER ROLE " + name + " NOLOGIN",
		"GRANT " + name + " TO CURRENT_USER",
	} {
		if _, err := b.db.Exec(ctx, stmt); err != nil {
			return err
		}
	}
	if _, err := b.db.Exec(ctx, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = $1", role); err != nil {
		return err
	}
	return pgx.BeginFunc(ctx, b.db, func(tx pgx.Tx) error {
		for _, stmt := range []string{
			"REASSIGN OWNED BY " + name + " TO CURRENT_USER",
			"DROP OWNED BY " + name,
			"DROP ROLE " + name,
		} {
			if _, err := tx.Exec(ctx, stmt); err != nil {
				return err
			}
		}
		return nil
	})
}
