"""MacContestLogger window plugins, protocol 1 - a single-file helper (Python 3 standard library only).

Copy this file next to your plugin's executable and import it:

    import mcl

    plugin = mcl.Plugin()

    @plugin.on_start
    def start(hello):
        plugin.set_window("main", [mcl.text("Hello " + (hello.get("band") or "?"), style="title")])

    @plugin.on("qso-logged")
    def logged(qso):
        count = plugin.request("log.count")["count"]
        plugin.set_window("main", [mcl.text(f"{count} QSOs")])

    @plugin.on_click("refresh")
    def refresh(event):
        ...

    plugin.run()

Handlers run one at a time on the main thread, in the order the app sent the messages. A handler may call
`request` (it blocks until the app answers; the answers are read on a background thread). See
docs/plugin-windows.md for the protocol.
"""
import json
import sys
import threading
import queue

PROTOCOL = 1

__all__ = [
    "Plugin", "PluginError", "text", "table", "row", "cell", "column", "list_", "item", "button", "toggle",
    "progress", "tabs", "tab",
]


class PluginError(Exception):
    """An error answer to a request (`code` and `message` from the app)."""

    def __init__(self, code, message):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


class Plugin:
    def __init__(self, stdin=None, stdout=None):
        self._stdin = stdin or sys.stdin
        self._stdout = stdout or sys.stdout
        self._write_lock = threading.Lock()
        self._id_lock = threading.Lock()
        self._next_id = 1
        self._waiting = {}
        self._inbox = queue.Queue()
        self._start = []
        self._events = {}
        self._ui = []
        self.hello = None

    # -- registration -------------------------------------------------------------------------------------------

    def on_start(self, handler):
        """`handler(hello)` after the app's hello (the plugin has already answered `ready`)."""
        self._start.append(handler)
        return handler

    def on(self, event):
        """`handler(data)` for an event (also list it under `events` in plugin.json, or it is never sent)."""
        def register(handler):
            self._events.setdefault(event, []).append(handler)
            return handler
        return register

    def on_ui(self, handler):
        """`handler(event)` for every interaction (`window`, `action`, `target`, `row`, `rowId`, `value`)."""
        self._ui.append((None, None, None, handler))
        return handler

    def on_click(self, target, window=None, double=False):
        """`handler(event)` for a click (or a double click) on the button, table or list `target`."""
        action = "double-click" if double else "click"
        def register(handler):
            self._ui.append((window, action, target, handler))
            return handler
        return register

    def on_change(self, target, window=None):
        """`handler(event)` when the toggle `target` changes (`event["value"]`)."""
        def register(handler):
            self._ui.append((window, "change", target, handler))
            return handler
        return register

    # -- sending ------------------------------------------------------------------------------------------------

    def send(self, message):
        line = json.dumps(message, ensure_ascii=False, separators=(",", ":"))
        with self._write_lock:
            self._stdout.write(line + "\n")
            self._stdout.flush()

    def set_window(self, window, elements):
        """Replaces the content of `window` with a list of elements (see the builders below)."""
        self.send({"type": "set", "window": window, "content": {"elements": list(elements)}})

    def log(self, text):
        """A line in the app's messages window."""
        self.send({"type": "log", "text": str(text)})

    def request(self, method, timeout=30, **params):
        """Asks the app (read only in protocol 1) and returns the result; raises PluginError on an error answer."""
        with self._id_lock:
            request_id = self._next_id
            self._next_id += 1
            slot = queue.Queue(maxsize=1)
            self._waiting[request_id] = slot
        self.send({"type": "request", "id": request_id, "method": method, "params": params})
        try:
            answer = slot.get(timeout=timeout)
        except queue.Empty:
            raise PluginError("timeout", f"no answer to {method}") from None
        finally:
            with self._id_lock:
                self._waiting.pop(request_id, None)
        if answer is None:
            raise PluginError("closed", "the app closed the connection")
        if "error" in answer:
            error = answer["error"] or {}
            raise PluginError(error.get("code", "error"), error.get("message", ""))
        return answer.get("result")

    # -- the loop -----------------------------------------------------------------------------------------------

    def run(self):
        """Reads the app's messages until it closes the input (the window closed, or the app quits)."""
        reader = threading.Thread(target=self._read, daemon=True)
        reader.start()
        while True:
            message = self._inbox.get()
            if message is None:
                return
            try:
                self._dispatch(message)
            except Exception as error:  # a broken handler must not end the plugin
                print(f"handler failed: {error!r}", file=sys.stderr, flush=True)

    def _read(self):
        for line in self._stdin:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if message.get("type") == "response":
                with self._id_lock:
                    slot = self._waiting.get(message.get("id"))
                if slot is not None:
                    slot.put(message)
                continue
            self._inbox.put(message)
        with self._id_lock:
            for slot in self._waiting.values():
                slot.put(None)
        self._inbox.put(None)

    def _dispatch(self, message):
        kind = message.get("type")
        if kind == "hello":
            self.hello = message
            self.send({"type": "ready"})
            for handler in self._start:
                handler(message)
        elif kind == "event":
            for handler in self._events.get(message.get("event"), []):
                handler(message.get("data"))
        elif kind == "ui":
            for window, action, target, handler in self._ui:
                if window is not None and window != message.get("window"):
                    continue
                if action is not None and action != message.get("action"):
                    continue
                if target is not None and target != message.get("target"):
                    continue
                handler(message)


# -- element builders (styles: normal, title, muted, warn, new, dupe, mult) ------------------------------------

def _styled(fields, style):
    if style:
        fields["style"] = style
    return fields


def text(value, style=None):
    return _styled({"type": "text", "text": str(value)}, style)


def column(title, align=None):
    return {"title": title, "align": align} if align else {"title": title}


def cell(value, style=None):
    return _styled({"text": str(value)}, style)


def row(cells, id=None, style=None):
    fields = {"cells": list(cells)}
    if id is not None:
        fields["id"] = str(id)
    return _styled(fields, style)


def table(columns, rows, id=None):
    """A table; with an `id` its rows send click and double-click events (`row`, `rowId`)."""
    fields = {"type": "table", "columns": list(columns), "rows": list(rows)}
    if id is not None:
        fields["id"] = id
    return fields


def item(value, id=None, style=None):
    fields = {"text": str(value)}
    if id is not None:
        fields["id"] = str(id)
    return _styled(fields, style)


def list_(items, id=None):
    fields = {"type": "list", "items": list(items)}
    if id is not None:
        fields["id"] = id
    return fields


def button(id, label, enabled=True):
    return {"type": "button", "id": id, "label": label, "enabled": bool(enabled)}


def toggle(id, label, value):
    return {"type": "toggle", "id": id, "label": label, "value": bool(value)}


def progress(value, maximum, label=None):
    fields = {"type": "progress", "value": value, "max": maximum}
    if label is not None:
        fields["label"] = label
    return fields


def tab(id, title, elements):
    return {"id": id, "title": title, "elements": list(elements)}


def tabs(tab_list, id=None):
    fields = {"type": "tabs", "tabs": list(tab_list)}
    if id is not None:
        fields["id"] = id
    return fields
