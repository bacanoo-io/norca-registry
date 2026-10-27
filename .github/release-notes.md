## Norca pack registry {{VERSION}}

<!-- Draft release: add the highlights and the changes of this release here before publishing. -->

### Packs

{{PACKS}}

Each pack's README describes its variables, requirements and the licenses of the software it installs.

### Usage

```shell
norca pack registry add norca {{REPO_URL}} --ref={{TAG}}
norca pack run <pack> --registry=norca
```

### Source code and license

The packs, examples and scripts of this release are available under the Mozilla Public License 2.0 at {{TAG_URL}}. The packs reference third-party container images and binaries (their licenses are named in each pack's README); none of them is shipped in this repository or its releases. Norca is an independent fork of HashiCorp Nomad v1.6.5 (MPL 2.0); it is not a product of HashiCorp or IBM and is not affiliated with them.
