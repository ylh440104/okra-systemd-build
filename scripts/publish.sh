#!/bin/bash
set -euo pipefail

RepositorySlug="${GITHUB_REPOSITORY:-ylh440104/okra-systemd-build}"
ReleaseTag="${ReleaseTag:-packages}"
ArtifactRoot="${1:-out}"
Token="${GH_TOKEN:-${PublishToken:-}}"

[ -n "$Token" ] || { echo "missing GH_TOKEN" >&2; exit 1; }

Api="https://api.github.com/repos/${RepositorySlug}"

echo "== syncing checksums"
git config user.name "OkraLinux Build"
git config user.email "build@okralinux.cn"
git add scripts out README.md .gitignore 2>/dev/null || true
if git diff --cached --quiet; then
	echo "no metadata change"
else
	git commit -m "update checksums"
	git push
fi

echo "== uploading artifacts to release ${ReleaseTag}"
ReleaseId="$(curl -sS -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/tags/${ReleaseTag}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"

if [ -z "$ReleaseId" ]; then
	echo "creating release ${ReleaseTag}"
	curl -sS -X POST -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" \
		"${Api}/releases" \
		-d "{\"tag_name\":\"${ReleaseTag}\",\"name\":\"${ReleaseTag}\",\"body\":\"OAA packages\"}" > /dev/null
	ReleaseId="$(curl -sS -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/tags/${ReleaseTag}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
fi

[ -n "$ReleaseId" ] || { echo "cannot resolve release" >&2; exit 1; }
echo "release id ${ReleaseId}"

Uploaded=0
while IFS= read -r Archive; do
	[ -f "$Archive" ] || continue
	ArchiveName="$(basename "$Archive")"
	Existing="$(curl -sS -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/${ReleaseId}/assets?per_page=100" \
		| python3 -c "import json,sys; print(' '.join(str(a['id']) for a in json.load(sys.stdin) if a['name']=='${ArchiveName}'))")"
	for AssetId in $Existing; do
		curl -sS -X DELETE -H "Authorization: Bearer ${Token}" -H "Accept: application/vnd.github+json" "${Api}/releases/assets/${AssetId}" > /dev/null
	done
	UploadUrl="https://uploads.github.com/repos/${RepositorySlug}/releases/${ReleaseId}/assets?name=${ArchiveName}"
	curl -sS -X POST -H "Authorization: Bearer ${Token}" -H "Content-Type: application/octet-stream" --data-binary "@${Archive}" "$UploadUrl" > /dev/null
	echo "uploaded $ArchiveName"
	Uploaded=$((Uploaded + 1))
done < <(find "$ArtifactRoot" -name '*.oaa' | sort)

echo "uploaded ${Uploaded} files to ${RepositorySlug} release ${ReleaseTag}"