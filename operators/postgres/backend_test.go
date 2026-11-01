// SPDX-FileCopyrightText: 2026 Norca contributors
// SPDX-License-Identifier: MPL-2.0

package main

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/bacanoo-io/norca/nomad/controller/secrets"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestRoleOf(t *testing.T) {
	const lease = "2b0f4f8e-7c1d-4d55-9a8e-3f7d1e2c9b10"
	const role = "v_2b0f4f8e7c1d4d559a8e3f7d1e2c9b10"
	b := newBackend(nil, &pgx.ConnConfig{}, "v_", time.Hour)
	for in, want := range map[string]string{
		lease:                                lease2role(lease),
		role:                                 role,
		"postgres":                           "",
		"":                                   "",
		"v_abc":                              "",
		role + "; x":                         "",
		"V_2B0F4F8E7C1D4D559A8E3F7D1E2C9B10": "",
	} {
		if got := b.roleOf(in); got != want {
			t.Errorf("roleOf(%q) = %q, want %q", in, got, want)
		}
	}

	// Another prefix owns other roles.
	other := newBackend(nil, &pgx.ConnConfig{}, "app_", time.Hour)
	if got := other.roleOf(role); got != "" {
		t.Errorf("got %q", got)
	}
	if got, want := other.roleOf(lease), "app_2b0f4f8e7c1d4d559a8e3f7d1e2c9b10"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func lease2role(lease string) string { return "v_" + strings.ReplaceAll(lease, "-", "") }

func TestCheckPrefix(t *testing.T) {
	for _, prefix := range []string{"v_", "app_", "_x", "a", strings.Repeat("a", 31)} {
		if err := checkPrefix(prefix); err != nil {
			t.Errorf("%q: %v", prefix, err)
		}
	}
	for _, prefix := range []string{"", "1a", "V_", "a-b", `a"`, "pg_x", strings.Repeat("a", 32)} {
		if err := checkPrefix(prefix); err == nil {
			t.Errorf("%q must be refused", prefix)
		}
	}
}

func TestOptions(t *testing.T) {
	good := options{prefix: "v_", sweepInterval: time.Minute}
	if err := good.check(); err != nil {
		t.Fatal(err)
	}
	for _, o := range []options{{prefix: ""}, {prefix: "v_", sweepInterval: -1}, {prefix: "v_", sweepGrace: -1}} {
		if err := o.check(); err == nil {
			t.Errorf("%+v must be refused", o)
		}
	}
}

func TestRoleList(t *testing.T) {
	if got := roleList(` orders_rw, a"b ,,`); got != `"orders_rw", "a""b"` {
		t.Fatalf("got %s", got)
	}
	if got := roleList(" , "); got != "" {
		t.Fatalf("got %q", got)
	}
}

func TestScramVerifier(t *testing.T) {
	v, err := scramVerifier("secret")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(v, "SCRAM-SHA-256$4096:") || strings.Contains(v, "secret") {
		t.Fatalf("got %s", v)
	}
	other, _ := scramVerifier("secret")
	if v == other {
		t.Fatal("the salt must differ")
	}
}

// fixture connects to the server of POSTGRES_TEST_URL with a superuser, and
// returns a backend whose admin has only CREATEROLE, as documented.
func fixture(t *testing.T) (*backend, *pgxpool.Pool, string) {
	t.Helper()
	root := os.Getenv("POSTGRES_TEST_URL")
	if root == "" {
		t.Skip("POSTGRES_TEST_URL is not set")
	}
	ctx := context.Background()
	su, err := pgxpool.New(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(su.Close)

	// Every test has its own admin, and from PostgreSQL 16 an admin can't drop
	// the roles of another one: no role may outlive its test.
	t.Cleanup(func() {
		rows, err := su.Query(ctx, `SELECT rolname FROM pg_roles WHERE rolname ~ '^(v|app)_[0-9a-f]{32}$'`)
		if err != nil {
			t.Error(err)
			return
		}
		roles, err := pgx.CollectRows(rows, pgx.RowTo[string])
		if err != nil {
			t.Error(err)
			return
		}
		for _, role := range roles {
			if _, err := su.Exec(ctx, fmt.Sprintf("DROP OWNED BY %s", role)); err != nil {
				t.Error(err)
			}
			if _, err := su.Exec(ctx, fmt.Sprintf("DROP ROLE %s", role)); err != nil {
				t.Error(err)
			}
		}
	})

	suffix := fmt.Sprintf("%x", time.Now().UnixNano())
	admin, group := "op_"+suffix, "grp_"+suffix
	for _, stmt := range []string{
		fmt.Sprintf("CREATE ROLE %s LOGIN CREATEROLE PASSWORD 'admin'", admin),
		fmt.Sprintf("CREATE ROLE %s NOLOGIN", group),
		fmt.Sprintf("GRANT %s TO %s WITH ADMIN OPTION", group, admin),
		fmt.Sprintf("CREATE SCHEMA s_%s", suffix),
		fmt.Sprintf("GRANT ALL ON SCHEMA s_%s TO %s", suffix, group),
		fmt.Sprintf("CREATE TABLE s_%s.orders (id int)", suffix),
		fmt.Sprintf("GRANT SELECT ON s_%s.orders TO %s", suffix, group),
	} {
		if _, err := su.Exec(ctx, stmt); err != nil {
			t.Fatalf("%s: %v", stmt, err)
		}
	}

	config, err := pgxpool.ParseConfig(root)
	if err != nil {
		t.Fatal(err)
	}
	config.ConnConfig.User, config.ConnConfig.Password = admin, "admin"
	db, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	return newBackend(db, config.ConnConfig, "v_", time.Hour), su, group
}

// uuid returns a new lease ID: the roles stay in the server between runs.
func uuid() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// login connects with the items of a credential.
func login(t *testing.T, items map[string]string) (*pgx.Conn, error) {
	t.Helper()
	config, err := pgx.ParseConfig(items["uri"] + "?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	return pgx.ConnectConfig(context.Background(), config)
}

func issue(t *testing.T, b *backend, lease, group string, ttl time.Duration) *secrets.Credential {
	t.Helper()
	cred, err := b.Issue(context.Background(), &secrets.IssueRequest{
		LeaseID: lease, TTL: ttl, Config: map[string]string{"member_of": group},
	})
	if err != nil {
		t.Fatal(err)
	}
	return cred
}

func exists(t *testing.T, su *pgxpool.Pool, role string) bool {
	t.Helper()
	var n int
	if err := su.QueryRow(context.Background(), "SELECT count(*) FROM pg_roles WHERE rolname = $1", role).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n == 1
}

func revoke(t *testing.T, b *backend, refs ...string) {
	t.Helper()
	list := map[string]time.Time{}
	for _, ref := range refs {
		list[ref] = time.Now().Add(time.Hour)
	}
	if err := b.Revoke(context.Background(), &secrets.RevokeRequest{Revoked: list}); err != nil {
		t.Fatal(err)
	}
}

func TestIssue_Login(t *testing.T) {
	b, su, group := fixture(t)
	ctx := context.Background()
	lease := uuid()
	cred := issue(t, b, lease, group, time.Hour)
	if cred.Ref != b.roleOf(lease) || cred.Items["username"] != cred.Ref {
		t.Fatalf("got %+v", cred.Ref)
	}

	conn, err := login(t, cred.Items)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	defer conn.Close(ctx)

	// The rights come from the group.
	var member bool
	if err := conn.QueryRow(ctx, "SELECT pg_has_role(current_user, $1, 'USAGE')", group).Scan(&member); err != nil || !member {
		var user string
		var groups []string
		_ = conn.QueryRow(ctx, "SELECT current_user").Scan(&user)
		_ = su.QueryRow(ctx, `SELECT array_agg(g.rolname::text) FROM pg_auth_members m JOIN pg_roles g ON g.oid = m.roleid
			JOIN pg_roles r ON r.oid = m.member WHERE r.rolname = $1`, cred.Ref).Scan(&groups)
		t.Fatalf("member=%v err=%v group=%s user=%s ref=%s groups=%v", member, err, group, user, cred.Ref, groups)
	}

	// The role has nothing beyond login.
	var super, createrole, createdb bool
	err = su.QueryRow(ctx, "SELECT rolsuper, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname = $1", cred.Ref).
		Scan(&super, &createrole, &createdb)
	if err != nil || super || createrole || createdb {
		t.Fatalf("attributes %v %v %v, err %v", super, createrole, createdb, err)
	}
}

func TestIssue_Idempotent(t *testing.T) {
	b, _, group := fixture(t)
	lease := uuid()
	first := issue(t, b, lease, group, time.Hour)
	second := issue(t, b, lease, group, time.Hour)
	if first.Ref != second.Ref {
		t.Fatalf("refs %s %s", first.Ref, second.Ref)
	}
	// The answer of the first call was lost: only the last password counts.
	if _, err := login(t, first.Items); err == nil {
		t.Fatal("the first password must be replaced")
	}
	conn, err := login(t, second.Items)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	conn.Close(context.Background())
}

func TestIssue_Invalid(t *testing.T) {
	b, _, _ := fixture(t)
	ctx := context.Background()
	for name, req := range map[string]*secrets.IssueRequest{
		"no group":      {LeaseID: uuid(), TTL: time.Hour},
		"unknown group": {LeaseID: uuid(), TTL: time.Hour, Config: map[string]string{"member_of": "no_such_group"}},
		"bad lease":     {LeaseID: "postgres", TTL: time.Hour, Config: map[string]string{"member_of": "x"}},
	} {
		_, err := b.Issue(ctx, req)
		var invalid *secrets.Invalid
		if !errors.As(err, &invalid) {
			t.Errorf("%s: got %v, want Invalid", name, err)
		}
	}
}

func TestItems(t *testing.T) {
	b := &backend{host: "db.internal", port: "5432", database: "orders"}
	items := b.items(map[string]string{"sslmode": "require"}, "v_x", "p")
	if want := "postgres://v_x:p@db.internal:5432/orders?sslmode=require"; items["uri"] != want {
		t.Fatalf("got %s", items["uri"])
	}
	items = b.items(map[string]string{"host": "public", "port": "6432", "database": "other"}, "v_x", "p")
	if want := "postgres://v_x:p@public:6432/other"; items["uri"] != want {
		t.Fatalf("got %s", items["uri"])
	}
	if items["host"] != "public" || items["port"] != "6432" || items["database"] != "other" {
		t.Fatalf("got %v", items)
	}
}

func TestRenew_MovesValidUntil(t *testing.T) {
	b, su, group := fixture(t)
	ctx := context.Background()
	cred := issue(t, b, uuid(), group, time.Minute)

	validity := func() time.Time {
		var until time.Time
		if err := su.QueryRow(ctx, "SELECT rolvaliduntil FROM pg_roles WHERE rolname = $1", cred.Ref).Scan(&until); err != nil {
			t.Fatal(err)
		}
		return until
	}
	if left := time.Until(validity()); left > time.Minute+5*time.Second || left < 30*time.Second {
		t.Fatalf("left %s", left)
	}
	if _, err := b.Renew(ctx, &secrets.RenewRequest{Ref: cred.Ref, TTL: time.Hour}); err != nil {
		t.Fatal(err)
	}
	if left := time.Until(validity()); left < 59*time.Minute {
		t.Fatalf("left %s", left)
	}

	revoke(t, b, cred.Ref)
	if _, err := b.Renew(ctx, &secrets.RenewRequest{Ref: cred.Ref, TTL: time.Hour}); err == nil {
		t.Fatal("renewing a role that is gone must fail")
	}
	var invalid *secrets.Invalid
	if _, err := b.Renew(ctx, &secrets.RenewRequest{Ref: "postgres", TTL: time.Hour}); !errors.As(err, &invalid) {
		t.Fatalf("got %v", err)
	}
}

func TestRevoke_EndsConnectionsAndKeepsObjects(t *testing.T) {
	b, su, group := fixture(t)
	ctx := context.Background()
	cred := issue(t, b, uuid(), group, time.Hour)
	conn, err := login(t, cred.Items)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	defer conn.Close(ctx)

	var schema string
	if err := su.QueryRow(ctx, "SELECT nspname FROM pg_namespace WHERE has_schema_privilege($1, oid, 'CREATE') AND nspname LIKE 's\\_%' ORDER BY oid DESC LIMIT 1", group).Scan(&schema); err != nil {
		t.Fatal(err)
	}
	table := schema + ".made_by_task"
	if _, err := conn.Exec(ctx, "CREATE TABLE "+table+" (id int)"); err != nil {
		t.Fatal(err)
	}

	revoke(t, b, cred.Ref)
	if exists(t, su, cred.Ref) {
		t.Fatal("the role must be gone")
	}
	if _, err := conn.Exec(ctx, "SELECT 1"); err == nil {
		t.Fatal("the open connection must be ended")
	}
	if _, err := login(t, cred.Items); err == nil {
		t.Fatal("the login must fail")
	}
	var owner string
	if err := su.QueryRow(ctx, "SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid = $1::regclass", table).Scan(&owner); err != nil {
		t.Fatalf("the table must stay: %v", err)
	}
	if owner != b.db.Config().ConnConfig.User {
		t.Fatalf("owner %s", owner)
	}
}

func TestRevoke_Refs(t *testing.T) {
	b, su, group := fixture(t)
	lease := uuid()
	cred := issue(t, b, lease, group, time.Hour)
	admin := b.db.Config().ConnConfig.User

	// Unknown references, and roles of others, are left alone.
	revoke(t, b, "postgres", admin, group, b.roleOf(uuid()), "")
	if !exists(t, su, admin) || !exists(t, su, group) || !exists(t, su, cred.Ref) {
		t.Fatal("nothing may be dropped")
	}

	// An issue that did not finish is revoked by its lease ID.
	revoke(t, b, lease)
	if exists(t, su, cred.Ref) {
		t.Fatal("the role must be gone")
	}

	// The list comes again.
	revoke(t, b, lease, cred.Ref)
}

func TestSweep(t *testing.T) {
	b, su, group := fixture(t)
	ctx := context.Background()
	expired := issue(t, b, uuid(), group, -2*b.grace)
	recent := issue(t, b, uuid(), group, -b.grace/2)
	live := issue(t, b, uuid(), group, time.Hour)
	if _, err := su.Exec(ctx, fmt.Sprintf("CREATE ROLE %s_other LOGIN VALID UNTIL '2000-01-01'", group)); err != nil {
		t.Fatal(err)
	}

	if err := b.sweep(ctx); err != nil {
		t.Fatal(err)
	}
	if exists(t, su, expired.Ref) {
		t.Fatal("an expired role must be gone")
	}
	if !exists(t, su, recent.Ref) || !exists(t, su, live.Ref) || !exists(t, su, group+"_other") {
		t.Fatal("only expired roles of the operator may be dropped")
	}
}

func TestPrefix_OwnsItsRoles(t *testing.T) {
	b, su, group := fixture(t)
	ctx := context.Background()
	other := newBackend(b.db, b.db.Config().ConnConfig, "app_", time.Second)

	mine := issue(t, other, uuid(), group, -time.Minute)
	if !strings.HasPrefix(mine.Ref, "app_") || mine.Items["username"] != mine.Ref {
		t.Fatalf("got %s", mine.Ref)
	}
	theirs := issue(t, b, uuid(), group, -2*b.grace)

	// Neither revokes nor sweeps the roles of the other.
	revoke(t, b, mine.Ref)
	if !exists(t, su, mine.Ref) {
		t.Fatal("the role of another prefix was dropped")
	}
	if err := other.sweep(ctx); err != nil {
		t.Fatal(err)
	}
	if exists(t, su, mine.Ref) || !exists(t, su, theirs.Ref) {
		t.Fatal("the sweep must drop its own roles only")
	}
}

func TestIssue_ExpiredLoginFails(t *testing.T) {
	b, _, group := fixture(t)
	cred := issue(t, b, uuid(), group, -time.Minute)
	if _, err := login(t, cred.Items); err == nil {
		t.Fatal("a login after VALID UNTIL must fail")
	}
	var pgErr *pgconn.PgError
	_, err := login(t, cred.Items)
	if !errors.As(err, &pgErr) {
		t.Fatalf("got %v", err)
	}
}
