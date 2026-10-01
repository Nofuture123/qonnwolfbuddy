"""Build the fake CLI snapshot from its already registered Space/pane responses."""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
workspaces = json.load(sys.stdin)["result"]["workspaces"]
focused = next((w["workspace_id"] for w in workspaces if w.get("focused")), workspaces[0]["workspace_id"])
tabs, panes = [], []
for path in root.glob("get-*.json"):
    pane = json.loads("\n".join(x for x in path.read_text().splitlines() if not x.startswith("#")))["result"]["pane"]
    panes.append(pane)
if (root / "tab-list.json").exists():
    tabs = json.loads((root / "tab-list.json").read_text())["result"]["tabs"]
# Focus belongs to an unrelated fixture Space and is stable across owned close.
focus_pane = {"pane_id": focused + ":pFocus", "tab_id": focused + ":tFocus", "workspace_id": focused}
panes.append(focus_pane)
tabs.append({"tab_id": focus_pane["tab_id"], "workspace_id": focused})
print(json.dumps({"result": {"snapshot": {"workspaces": workspaces, "tabs": tabs, "panes": panes,
    "focused_workspace_id": focused, "focused_tab_id": focus_pane["tab_id"], "focused_pane_id": focus_pane["pane_id"]}}}))
