import json
import re
import requests
import os
from datetime import datetime

bundle_id = "app.aidoku.Aidoku"
minimum_ios_version = "15.0"
json_file_name = ".github/workflows/supporting/altstore/apps.json"
github_repo = "Aidoku/Aidoku"

def fetch_latest_release(repo):
    api_url = f"https://api.github.com/repos/{repo}/releases"
    headers = {
        "Accept": "application/vnd.github+json",
    }
    try:
        response = requests.get(api_url, headers=headers)
        response.raise_for_status()
        releases = response.json()
        if len(releases) == 0:
            raise ValueError("No release found.")
        
        sorted_releases = sorted(releases, key=lambda release: datetime.strptime(release["published_at"], "%Y-%m-%dT%H:%M:%SZ"), reverse=True) # Sort from newest to oldest
        filtered_sorted_releases = list(filter(lambda release: release["draft"] == False and release["prerelease"] == False, sorted_releases)) # filter out drafts and prereleases
        if len(filtered_sorted_releases) == 0:
            raise ValueError("An error occured while sorting and filtering releases.")
        
        return filtered_sorted_releases[0]
    except requests.RequestException as e:
        print(f"Error fetching releases: {e}")
        raise

def remove_tags_and_characters(text):
    text = re.sub('<[^<]+?>', '', text)
    text = re.sub(r'#{1,6}\s?', '', text)
    text = re.sub(r'\*{2}', '', text)
    text = re.sub(r'-', '•', text)
    text = re.sub(r'`', '"', text)
    text = re.sub(r'\r\n', '\n', text)
    return text

def update_json_file(json_file, repo):
    latest_release = fetch_latest_release(repo)
    try:
        with open(json_file, "r") as file:
            data = json.load(file)
    except json.JSONDecodeError as e:
        print(f"Error reading JSON file: {e}")
        raise

    if "apps" not in data:
        print(f"There is no \"apps\" key in {json_file}.")
        raise
    
    apps_data = data["apps"]
    if len(apps_data) == 0:
        print(f"There is no data for \"apps\" key in {json_file}.")
        raise
        
    app = apps_data[0]
    if "versions" not in app:
        app["versions"] = []
    
    
    if "assets" not in latest_release:
        print("There is no \"assets\" key in latest release JSON. It may mean there are no assets other than source code tarball and zipball.")
        raise
        
    assets = latest_release["assets"]
    if len(assets) == 0:
        print("There are no assets other than source code tarball and zipball in latest release JSON.")
        raise
    
    asset_to_use = None
    for asset in assets:
        if asset["name"].endswith(".ipa"):
            asset_to_use = asset
            break
            
    if asset_to_use is None:
        print(".ipa file is not found in assets")
        raise
    
    data["featuredApps"] = [bundle_id]
    app["bundleIdentifier"] = bundle_id
    tag = latest_release["tag_name"]
    full_version = tag.lstrip('v')
    version = re.search(r"(\d+\.\d+(\.\d+)?)", full_version).group(1)
    version_entry_exists = any(item["version"] == version for item in app["versions"])
    if not version_entry_exists:
        version_date = latest_release["published_at"]
        date_obj = datetime.strptime(version_date, "%Y-%m-%dT%H:%M:%SZ")
        version_date = date_obj.strftime("%Y-%m-%d")

        description = latest_release["body"]
        keypharse = "Aidoku Release Information"
        if keypharse in description:
            description = description.split(keypharse, 1)[1].strip()

        description = remove_tags_and_characters(description)

        download_url = asset_to_use["browser_download_url"]
        size = asset_to_use["size"]

        version_entry = {
            "version": version,
            "date": version_date,
            "localizedDescription": description,
            "downloadURL": download_url,
            "size": size,
            "minOSVersion": minimum_ios_version
        }
        app["versions"].insert(0, version_entry)
        
# If news update is wanted
###
#    if "news" not in data:
#        data["news"] = []
#
#    news_identifier = f"release-{full_version}"
#    news_entry_exists = any(item["identifier"] == news_identifier for item in data["news"])
#    if not news_entry_exists:
#        date_string = date_obj.strftime("%Y/%m/%d")
#        news_entry = {
#            "appID": bundle_id,
#            "caption": f"New version of Aidoku just got released!",
#            "date": latest_release["published_at"],
#            "identifier": news_identifier,
#            "notify": True,
#            "tintColor": "ff375f",
#            "title": f"v{full_version}",
#            "url": f"https://github.com/{repo}/releases/tag/{tag}"
#        }
#        data["news"].insert(0, news_entry)
#
#    if not version_entry_exists and not news_entry_exists:
###

# If news update is NOT wanted
###
    if not version_entry_exists:
###
        try:
            with open(json_file, "w") as file:
                json.dump(data, file, indent=2)
            print("JSON file updated successfully.")
        except IOError as e:
            print(f"Error writing to JSON file: {e}")
            raise
    else:
        print("No need to update JSON")

def main():
    try:
        update_json_file(json_file_name, github_repo)
    except Exception as e:
        print(f"An error occurred: {e}")
        raise

if __name__ == "__main__":
    main()
