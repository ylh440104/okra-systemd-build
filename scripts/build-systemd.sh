#!/bin/bash
set -euo pipefail

Version="${SystemdVersion:-262}"
Release=1
Architecture="${Architecture:-aarch64}"
RepositoryRoot="$(cd "$(dirname "$0")/.." && pwd)"
WorkRoot="${RUNNER_TEMP:-/tmp}/okra-systemd"
SourceDirectory="$WorkRoot/source"
BuildDirectory="$WorkRoot/build"
InstallRoot="$WorkRoot/install"
PackageDirectory="$WorkRoot/package"
ArtifactDirectory="${RUNNER_TEMP:-/tmp}/okra-artifacts"
OutputDirectory="$RepositoryRoot/out"
Archive="$WorkRoot/systemd-$Version.tar.gz"

. "$RepositoryRoot/scripts/meson-options.sh"

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"
export LC_ALL=C
export TZ=UTC
export CFLAGS="-O2 -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fno-plt -Wformat -Werror=format-security"
export LDFLAGS="-Wl,-z,relro,-z,now -Wl,-z,noexecstack"

rm -rf "$WorkRoot"
mkdir -p "$WorkRoot" "$SourceDirectory" "$ArtifactDirectory" "$OutputDirectory"

echo "== fetching systemd $Version"
curl -fsSL --http1.1 --retry 5 --retry-delay 3 --retry-all-errors \
meson-options.sh -o "$Archive" "https://github.com/systemd/systemd/archive/refs/tags/v$Version.tar.gz"
SourceSum="$(sha256sum "$Archive" | awk '{print $1}')"
echo "source sha256 $SourceSum"

tar -xf "$Archive" -C "$SourceDirectory" --strip-components=1

echo "== meson setup"
cd "$SourceDirectory"
meson setup "$BuildDirectory" "${MESON_OPTIONS[@]}"

echo "== ninja build"
ninja -C "$BuildDirectory" -j"$(nproc)"

echo "== install"
DESTDIR="$InstallRoot" fakeroot ninja -C "$BuildDirectory" install

echo "== linked libraries check"
for Binary in "$InstallRoot/usr/lib/systemd/systemd" "$InstallRoot/usr/bin/systemctl" "$InstallRoot/usr/lib/systemd/systemd-logind"; do
meson-options.sh [ -f "$Binary" ] || continue
meson-options.sh echo "-- $(basename "$Binary")"
meson-options.sh readelf -d "$Binary" 2>/dev/null | grep NEEDED | grep -oE 'lib[a-z0-9_-]+\.so[0-9.]*' | sort -u | tr '\n' ' ' || true
meson-options.sh echo
done

echo "== assembling package"
mkdir -p "$PackageDirectory/rootfs" "$PackageDirectory/scripts"
cp -a "$InstallRoot"/. "$PackageDirectory/rootfs"/
find "$PackageDirectory" -name '.l2s.*' -delete
find "$PackageDirectory/rootfs" -name '*.a' -delete
find "$PackageDirectory/rootfs" -name '*.la' -delete

InstalledSize="$(du -sm "$PackageDirectory/rootfs" | cut -f1)"

FileList=""
for SearchDirectory in usr/bin usr/sbin usr/lib usr/libexec usr/share lib lib64 sbin bin etc; do
Target="$PackageDirectory/rootfs/$SearchDirectory"
[ -d "$Target" ] || continue
while IFS= read -r FoundFile; do
FileList="${FileList}${SearchDirectory}/${FoundFile}"$'\n'
done < <(cd "$Target" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | sort)
done

{
echo "name: systemd"
echo "namespace: app"
echo "version: $Version"
echo "release: $Release"
echo "description: systemd init and service manager"
echo "architecture: $Architecture"
echo "maintainer: OkraLinux Team <maintainer@okralinux.cn>"
echo "installed_size: $InstalledSize"
echo "dependencies:"
for Dependency in glibc util-linux kmod libseccomp pcre2 zstd xz bzip2 zlib; do
echo "  - $Dependency"
done
echo "files:"
if [ -n "$FileList" ]; then
while IFS= read -r ListedFile; do
[ -n "$ListedFile" ] || continue
echo "  - /$ListedFile"
done <<< "$FileList"
else
echo "  - /"
fi
} > "$PackageDirectory/meta.yaml"

ArchiveName="systemd-$Version-$Release.$Architecture.oaa"
PackageOutput="$ArtifactDirectory/systemd"
rm -rf "$PackageOutput"
mkdir -p "$PackageOutput"
cd "$PackageDirectory"
tar --zstd -cf "$PackageOutput/$ArchiveName" \
--sort=name --mtime="@${SOURCE_DATE_EPOCH}" --clamp-mtime \
--owner=0 --group=0 --numeric-owner \
meta.yaml rootfs scripts
cd "$PackageOutput"
sha256sum "$ArchiveName" > "${ArchiveName}.sha256"

MetadataOutput="$OutputDirectory/systemd"
rm -rf "$MetadataOutput"
mkdir -p "$MetadataOutput"
cp -f "${ArchiveName}.sha256" "$MetadataOutput/"
echo "${SourceSum}  https://github.com/systemd/systemd/archive/refs/tags/v${Version}.tar.gz" > "$MetadataOutput/systemd-${Version}-${Release}.sources"
echo "${SourceSum}  https://github.com/systemd/systemd/archive/refs/tags/v${Version}.tar.gz" > "$PackageOutput/systemd-${Version}-${Release}.sources"

echo "== built $ArchiveName"
cat "${ArchiveName}.sha256"
