"""Build the AltStore / SideStore source for a fork.

Unlike update_altstore_json.py (which reads the upstream release), this script
takes the freshly built IPA from the fork's CI run and writes apps.json with
download links pointing at the fork's own GitHub release.

Environment:
    GITHUB_REPOSITORY  owner/repo of the fork (set by GitHub Actions)
    IPA_PATH           path to the built .ipa
    RELEASE_TAG        tag of the release the IPA is attached to
    RELEASE_NOTES      text shown in AltStore for this version
    SOURCE_DIR         checkout of the altstore branch (existing apps.json is kept)
"""

import io
import json
import os
import plistlib
import zipfile
from datetime import datetime, timezone

bundle_id = "app.aidoku.Aidoku"
minimum_ios_version = "15.0"
max_versions = 10
template_path = ".github/workflows/supporting/altstore/apps.json"


def read_ipa_info(ipa_path):
    with zipfile.ZipFile(ipa_path, "r") as ipa:
        for name in ipa.namelist():
            if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist"):
                plist = plistlib.load(io.BytesIO(ipa.read(name)))
                return plist["CFBundleShortVersionString"], plist["CFBundleVersion"]
    raise FileNotFoundError("Info.plist not found in IPA")


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    owner = repo.split("/")[0]
    ipa_path = os.environ["IPA_PATH"]
    tag = os.environ["RELEASE_TAG"]
    notes = os.environ.get("RELEASE_NOTES", "").strip() or "Nightly build"
    output_path = os.path.join(os.environ["SOURCE_DIR"], "apps.json")

    # keep previous versions if the source already exists on the altstore branch
    base_path = output_path if os.path.exists(output_path) else template_path
    with open(base_path, "r") as file:
        data = json.load(file)

    data["name"] = f"Aidoku ({owner})"
    data["identifier"] = f"app.aidoku.altstore.{owner.lower()}"
    data["sourceURL"] = f"https://raw.githubusercontent.com/{repo}/refs/heads/altstore/apps.json"
    data["subtitle"] = f"Aidoku builds from the {repo} fork"
    data["featuredApps"] = [bundle_id]
    data.setdefault("news", [])

    app = data["apps"][0]
    app["bundleIdentifier"] = bundle_id
    versions = app.setdefault("versions", [])

    version, build = read_ipa_info(ipa_path)
    # drop the same build if the workflow is re-run, and any upstream entries
    versions[:] = [
        v for v in versions
        if not (v["version"] == version and v.get("buildVersion") == build)
        and f"github.com/{repo}/" in v.get("downloadURL", "")
    ]
    versions.insert(0, {
        "version": version,
        "buildVersion": build,
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": notes,
        "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/Aidoku.ipa",
        "size": os.path.getsize(ipa_path),
        "minOSVersion": minimum_ios_version,
    })
    del versions[max_versions:]

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as file:
        json.dump(data, file, indent=2)
    print(f"Wrote {output_path}: {version} ({build}) -> {tag}")


if __name__ == "__main__":
    main()
