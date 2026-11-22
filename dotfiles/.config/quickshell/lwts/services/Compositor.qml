// Niri state for the whole shell (replaces Quickshell.Hyprland + every `hyprctl ... -j` poll).
// One long-lived `niri msg --json event-stream`: niri sends the full state first, then updates, so nothing is polled.
// Everything the shell needs from the compositor goes through here: workspaces, windows, focus, layout, outputs, actions.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  // ---- state (arrays/objects are replaced as a whole so bindings re-evaluate) ----
  property var workspaces: []       // [{id, idx, name, output, urgent, active, focused, activeWindowId}]
  property var windows: ({})        // id -> {id, title, app_id, pid, workspace_id, is_focused, is_floating, ...}
  property int focusedWindowId: -1
  property var layoutNames: []      // keyboard layouts, e.g. ["English (US)", "Ukrainian"]
  property int layoutIndex: 0
  property bool overviewOpen: false
  property var outputs: ({})        // name -> {name, make, model, modes, current_mode, vrr_*, logical:{x,y,width,height,scale,transform}}
  property bool connected: false
  property var casts: ({})          // stream_id -> {stream_id, session_id, target: "Nothing" | {Output:{name}} | {Window:{id}}, is_dynamic_target, is_active, pid, pw_node_id}

  // ---- derived ----
  readonly property var focusedWorkspace: workspaces.find(w => w.focused) || null
  readonly property int focusedWorkspaceId: focusedWorkspace ? focusedWorkspace.id : -1   // changes only on a real switch (not on every event)
  readonly property string focusedOutput: focusedWorkspace ? focusedWorkspace.output : ""
  readonly property var focusedWindow: windows[focusedWindowId] || null
  readonly property string layoutName: layoutNames[layoutIndex] || ""
  readonly property var windowList: Object.values(windows)
  readonly property var castList: Object.values(casts)
  readonly property int castCount: castList.length
  function castTarget(c) {   // what a cast shows, for labels: "SCREEN DP-2" / the window title / "NOTHING"
    const t = c ? c.target : null;
    if (t && t.Output) return t.Output.name;
    if (t && t.Window) return (windows[t.Window.id] || {}).title || "WINDOW";
    return "NOTHING";
  }

  function workspacesOn(output) { return workspaces.filter(w => w.output === output).sort((a, b) => a.idx - b.idx) }
  function windowsOn(workspaceId) { return windowList.filter(w => w.workspace_id === workspaceId) }
  function outputFor(screen) { return screen ? (outputs[screen.name] || null) : null }

  // ---- notifications (the Hyprland rawEvent / onFocusedWorkspaceChanged replacements) ----
  signal windowOpened(var window)
  signal windowClosed(int id)
  signal outputFocused(string output)
  onFocusedOutputChanged: if (focusedOutput !== "") outputFocused(focusedOutput)

  // the empty workspace niri always keeps at the end of an output (idx of the last one)
  function lastIdx(output) { const l = workspacesOn(output); return l.length ? l[l.length - 1].idx : 1 }

  // ---- actions ----
  function act(args) { Quickshell.execDetached(["niri", "msg", "action"].concat(args)) }
  function focusWorkspace(idx) { act(["focus-workspace", String(idx)]) }                 // idx on the focused output
  function focusWindow(id) { act(["focus-window", "--id", String(id)]) }
  function closeWindow(id) { act(id === undefined ? ["close-window"] : ["close-window", "--id", String(id)]) }
  function switchLayout() { act(["switch-layout", "next"]) }
  function powerOffMonitors() { act(["power-off-monitors"]) }
  function powerOnMonitors() { act(["power-on-monitors"]) }
  function logout() { act(["quit", "--skip-confirmation"]) }
  function toggleOverview() { act(["toggle-overview"]) }
  function stopCasts() {   // one stop-cast per session (it stops every stream of it)
    const seen = {};
    castList.forEach(c => { if (!seen[c.session_id]) { seen[c.session_id] = true; act(["stop-cast", "--session-id", String(c.session_id)]) } });
  }
  function spawn(argv) { act(["spawn", "--"].concat(argv)) }

  // ---- event stream ----
  function _setWorkspaces(list) {
    root.workspaces = list.map(w => ({ id: w.id, idx: w.idx, name: w.name, output: w.output, urgent: w.is_urgent,
                                       active: w.is_active, focused: w.is_focused, activeWindowId: w.active_window_id }))
  }
  function _handle(ev) {
    const k = Object.keys(ev)[0], v = ev[k];
    switch (k) {
    case "WorkspacesChanged": _setWorkspaces(v.workspaces); break;
    case "WorkspaceActivated": {   // active: one per output; focused: the one that owns keyboard focus (only when v.focused)
      const out = (root.workspaces.find(w => w.id === v.id) || {}).output;
      root.workspaces = root.workspaces.map(w => Object.assign({}, w, {
        active: w.output === out ? w.id === v.id : w.active,
        focused: v.focused ? w.id === v.id : w.focused }));
      break;
    }
    case "WorkspaceActiveWindowChanged":
      root.workspaces = root.workspaces.map(w => w.id === v.workspace_id ? Object.assign({}, w, { activeWindowId: v.active_window_id }) : w); break;
    case "WorkspaceUrgencyChanged":
      root.workspaces = root.workspaces.map(w => w.id === v.id ? Object.assign({}, w, { urgent: v.urgent }) : w); break;
    case "WindowsChanged": {
      const m = {}; let f = -1;
      for (const w of v.windows) { m[w.id] = w; if (w.is_focused) f = w.id }
      root.windows = m; root.focusedWindowId = f; break;
    }
    case "WindowOpenedOrChanged": {
      const isNew = !(v.window.id in root.windows);
      const m = Object.assign({}, root.windows); m[v.window.id] = v.window; root.windows = m;
      if (isNew) root.windowOpened(v.window);
      if (v.window.is_focused) root.focusedWindowId = v.window.id;
      break;
    }
    case "WindowClosed": {
      const m = Object.assign({}, root.windows); delete m[v.id]; root.windows = m;
      root.windowClosed(v.id);
      if (root.focusedWindowId === v.id) root.focusedWindowId = -1;
      break;
    }
    case "WindowLayoutsChanged": {   // sizes / positions change without WindowOpenedOrChanged (fullscreen detection in OsdState needs them)
      const m = Object.assign({}, root.windows);
      for (const c of v.changes) if (m[c[0]]) m[c[0]] = Object.assign({}, m[c[0]], { layout: c[1] });
      root.windows = m; break;
    }
    case "WindowFocusChanged": root.focusedWindowId = v.id === null ? -1 : v.id; break;
    case "KeyboardLayoutsChanged": root.layoutNames = v.keyboard_layouts.names; root.layoutIndex = v.keyboard_layouts.current_idx; break;
    case "KeyboardLayoutSwitched": root.layoutIndex = v.idx; break;
    case "CastsChanged": { const m = {}; for (const c of v.casts) m[c.stream_id] = c; root.casts = m; break }
    case "CastStartedOrChanged": { const m = Object.assign({}, root.casts); m[v.cast.stream_id] = v.cast; root.casts = m; break }
    case "CastStopped": { const m = Object.assign({}, root.casts); delete m[v.stream_id]; root.casts = m; break }
    case "OverviewOpenedOrClosed": root.overviewOpen = v.is_open; break;
    case "ConfigLoaded": refreshOutputs(); break;   // outputs have no event of their own; a reload is the usual reason they change
    }
  }

  // Direct connection to $NIRI_SOCKET (no `niri msg` process): ask for the stream, read one JSON object per line.
  Socket {
    id: stream
    path: Quickshell.env("NIRI_SOCKET")
    connected: path !== ""
    onConnectedChanged: {
      root.connected = connected;
      if (connected) { write('"EventStream"\n'); flush() }
      else if (path !== "") restart.start()   // niri restarted / not up yet: keep trying, no busy loop
    }
    parser: SplitParser {
      onRead: line => {
        let ev = null;
        try { ev = JSON.parse(line) } catch (e) { return }
        root._handle(ev);
      }
    }
  }
  Timer { id: restart; interval: 1000; onTriggered: stream.connected = true }

  // ---- outputs (one-shot query; call again after changing monitors) ----
  function refreshOutputs() { outProc.running = true }
  Process {
    id: outProc
    command: ["niri", "msg", "--json", "outputs"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.outputs = JSON.parse(this.text) } catch (e) {} }
    }
  }
  Component.onCompleted: refreshOutputs()
}
