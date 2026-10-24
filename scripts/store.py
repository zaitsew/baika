#!/usr/bin/env python3
"""Baika's App Store settings that POLICY section 15 asks for, as code.

`availability`: every territory except China mainland.
`listing`: no model provider named in any store or TestFlight text.

Why CHN is off (POLICY section 15): every story is generative. Perform writes the script with
a generative model and narrates it with a generated voice, and Talk is a realtime voice model,
all through Fabrique Accounts (Anthropic, ElevenLabs and OpenAI). Generative AI in the China storefront needs a Chinese permit (MIIT / CAC)
that none of these providers has, and any app there also needs an ICP filing, which needs
a Chinese entity. Re-including China is the owner's call.

The setting is app-wide: it covers the iOS app and any later Mac build.

Usage:
    scripts/store.py availability            # show the current state (read-only)
    scripts/store.py availability --apply    # create or update the availability
    scripts/store.py listing                 # exit 1 if a listing text names a provider

Credentials and REST calls come from ~/ops/bin/testflight (the App Store Connect API key
in ~/.appstoreconnect/); this script never reads the key itself.
"""
import argparse
import importlib.machinery
import importlib.util
import json
import os
import re
import sys

BUNDLE_ID = "com.zaitsew.baika"
EXCLUDED = {"CHN"}  # China mainland: no generative-AI permit, no ICP filing (see above)
# Model providers stay out of the name, subtitle, description, keywords, What's New and What
# to Test. The privacy policy and the in-app AI consent still name every provider.
PROVIDERS = re.compile(r"openai|chatgpt|\bgpt|claude|anthropic|gemini|grok|elevenlabs|eleven labs", re.I)


def testflight():
    path = os.path.expanduser("~/ops/bin/testflight")
    loader = importlib.machinery.SourceFileLoader("testflight", path)
    spec = importlib.util.spec_from_loader("testflight", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def territories(tf, cfg) -> list[str]:
    return sorted(t["id"] for t in tf._all_pages(cfg, "/v1/territories?limit=200"))


def current(tf, cfg, app: str) -> tuple[dict[str, bool], dict[str, str]] | None:
    r = tf.api(cfg, f"/v1/apps/{app}/appAvailabilityV2", soft=(404,))
    if r.get("error") == 404:
        return None
    rows = tf._all_pages(
        cfg, f"/v2/appAvailabilities/{r['data']['id']}/territoryAvailabilities"
        "?include=territory&limit=200")
    return {row["relationships"]["territory"]["data"]["id"]: row["attributes"]["available"]
            for row in rows}, {row["relationships"]["territory"]["data"]["id"]: row["id"]
                               for row in rows}


def listing(tf, cfg, app: str) -> None:
    texts: list[tuple[str, dict]] = []
    for row in tf._all_pages(cfg, f"/v1/apps/{app}/betaAppLocalizations"):
        texts.append(("beta description", row["attributes"]))
    for info in tf._all_pages(cfg, f"/v1/apps/{app}/appInfos"):
        for row in tf._all_pages(cfg, f"/v1/appInfos/{info['id']}/appInfoLocalizations"):
            texts.append(("name and subtitle", row["attributes"]))
    for version in tf._all_pages(cfg, f"/v1/apps/{app}/appStoreVersions"):
        for row in tf._all_pages(
                cfg, f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations"):
            texts.append((f"version {version['attributes']['versionString']}", row["attributes"]))
    for build in tf._all_pages(cfg, f"/v1/builds?filter[app]={app}&limit=50"):
        for row in tf._all_pages(cfg, f"/v1/builds/{build['id']}/betaBuildLocalizations"):
            texts.append((f"what to test, build {build['attributes']['version']}",
                          row["attributes"]))
    hits = [(src, PROVIDERS.findall(json.dumps(a, ensure_ascii=False))) for src, a in texts]
    hits = [(src, sorted(set(h))) for src, h in hits if h]
    for src, words in hits:
        print(f"provider named in {src}: {', '.join(words)}")
    print(f"listing: {len(texts)} texts read, {len(hits)} name a model provider")
    if hits:
        sys.exit(1)


def availability(tf, cfg, app: str, apply: bool) -> None:
    state = current(tf, cfg, app)

    if state is None:
        print("availability: not set yet")
        if not apply:
            return
        ids = territories(tf, cfg)
        refs = [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in ids]
        included = [{
            "type": "territoryAvailabilities", "id": f"${{{t}}}",
            "attributes": {"available": t not in EXCLUDED},
            "relationships": {"territory": {"data": {"type": "territories", "id": t}}},
        } for t in ids]
        tf.write(cfg, "/v2/appAvailabilities", method="POST", body={
            "data": {
                "type": "appAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app}},
                    "territoryAvailabilities": {"data": refs},
                },
            },
            "included": included,
        })
        print(f"availability: created, {len(ids) - len(EXCLUDED & set(ids))} of {len(ids)} "
              f"territories on, off: {', '.join(sorted(EXCLUDED))}")
        return

    available, row_ids = state
    wrong = {t: v for t, v in available.items() if v == (t in EXCLUDED)}
    on = sum(available.values())
    print(f"availability: {on} of {len(available)} territories on; "
          f"CHN {'on' if available.get('CHN') else 'off'}")
    if not wrong:
        return
    print("differs from the rule: " + ", ".join(
        f"{t} {'on' if v else 'off'}" for t, v in sorted(wrong.items())))
    if not apply:
        sys.exit(1)
    for t in sorted(wrong):
        tf.write(cfg, f"/v1/territoryAvailabilities/{row_ids[t]}", method="PATCH", body={
            "data": {"type": "territoryAvailabilities", "id": row_ids[t],
                     "attributes": {"available": t not in EXCLUDED}}})
        print(f"· {t} → {'on' if t not in EXCLUDED else 'off'}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="command", required=True)
    a = sub.add_parser("availability", help="territories: all but China mainland")
    a.add_argument("--apply", action="store_true", help="write the availability")
    sub.add_parser("listing", help="no model provider in store or TestFlight text")
    args = p.parse_args()

    tf = testflight()
    cfg = tf.load_config()
    app = tf._app_id(cfg, BUNDLE_ID)
    if args.command == "availability":
        availability(tf, cfg, app, args.apply)
    else:
        listing(tf, cfg, app)


if __name__ == "__main__":
    main()
