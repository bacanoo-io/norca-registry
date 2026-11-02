module github.com/bacanoo-io/norca-registry/operators/postgres

go 1.27

toolchain go1.27.3

// Norca has no released modules yet: the SDK comes from a checkout of the Norca
// repository next to this one.
replace (
	github.com/bacanoo-io/norca/norca/api => ../../../norca/norca/api
	github.com/bacanoo-io/norca/norca/controller => ../../../norca/norca/controller
)

require (
	github.com/bacanoo-io/norca/norca/controller v0.0.0-00010101000000-000000000000
	github.com/jackc/pgx/v5 v5.7.6
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	golang.org/x/crypto v0.37.0 // indirect
	golang.org/x/sync v0.13.0 // indirect
	golang.org/x/text v0.24.0 // indirect
)
