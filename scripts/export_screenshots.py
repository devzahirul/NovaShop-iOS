#!/usr/bin/env python3
"""Copies named screenshot attachments exported from an .xcresult into docs/screenshots."""
import json, shutil, sys, os

source, destination = sys.argv[1], sys.argv[2]
os.makedirs(destination, exist_ok=True)
for test in json.load(open(os.path.join(source, "manifest.json"))):
    for attachment in test["attachments"]:
        name = attachment.get("suggestedHumanReadableName", "")
        if name.startswith(("light-", "dark-")):
            target = os.path.join(destination, name.split("_0_")[0] + ".png")
            shutil.copy(os.path.join(source, attachment["exportedFileName"]), target)
            print("→", target)
