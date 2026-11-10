# Library releases: one-time setup

How to set up a library repository to publish with
[`publish.gradle-library.yml`](../workflows/publish.gradle-library.md).
After this, releases happen by adding a `release:*` label to a pull request and merging it.

## 1. Create the release labels

```shell
gh label create release:major --color B60205 --description "Release a new major version on merge"
gh label create release:minor --color FBCA04 --description "Release a new minor version on merge"
gh label create release:patch --color 0E8A16 --description "Release a new patch version on merge"
```

## 2. Tag the latest existing release

The version is computed from `vX.Y.Z` tags. If the repository has none, tag the commit of the latest
version already published to `maven-releases`:

```shell
git tag v2.3.0 <sha>
git push origin v2.3.0
```

Without a tag, the workflow starts from `initial-version` (default `0.0.0`) and shows a warning.

## 3. Select the Nexus repository from the version

`build.gradle.kts` must publish snapshots and releases to different repositories, based on the version
suffix, and read credentials from the environment:

```kotlin
publishing {
    repositories {
        maven {
            val repo = if (version.toString().endsWith("SNAPSHOT")) "maven-snapshots-v2" else "maven-releases"
            url = uri("https://nexus.common-services.vydev.io/repository/$repo/")
            credentials {
                username = System.getenv("NEXUS_USERNAME")
                password = System.getenv("NEXUS_PASSWORD")
            }
        }
    }
}
```

Apply the `jacoco` plugin so the `jacocoTestReport` task exists, or override `gradle-operations`.

## 4. Set a local version

The workflow always passes `-Pversion=<version>`. For local builds, set a version that can never be
mistaken for a real release in `gradle.properties`:

```properties
version=0.0.0-LOCAL-SNAPSHOT
```

## 5. Add the workflow

Add the example caller from the [workflow docs](../workflows/publish.gradle-library.md#example), and
remove any old publish workflow so the library isn't published twice.

## Releasing

| You want | Do |
|---|---|
| Breaking change release | Add `release:major` to the PR, then merge |
| New feature release | Add `release:minor`, then merge |
| Bug fix release | Add `release:patch`, then merge |
| No release, just a snapshot | Merge without a release label |
| Test a PR from another project | Depend on `<next>-PR<number>-SNAPSHOT` (shown in the PR run's job summary) |

The old manual process (commit to remove `-SNAPSHOT`, publish, commit the next `-SNAPSHOT`) is no
longer needed.
