// MacContestLogger window plugins, protocol 1 — a single-file helper for Node.js (no packages needed).
//
// Copy this file next to your plugin's executable and require it:
//
//   #!/usr/bin/env node
//   const mcl = require("./mcl.js");
//   const plugin = new mcl.Plugin();
//
//   plugin.onStart(async (hello) => {
//     const { count } = await plugin.request("log.count");
//     plugin.setWindow("main", [mcl.text(`${count} QSOs`, "title"), mcl.button("refresh", "Refresh")]);
//   });
//   plugin.on("qso-logged", async () => { /* … */ });
//   plugin.onClick("refresh", async () => { /* … */ });
//   plugin.onKey("cq", async () => { await plugin.request("tx.fkey", { key: 1 }); });
//   plugin.run();
//
// Handlers may be async; they run one at a time in the order the app sent the messages, and `request` returns a
// promise of the result (rejected with an Error carrying `code`). See docs/plugin-windows.md for the protocol.
"use strict";

const readline = require("readline");

class PluginError extends Error {
  constructor(code, message) {
    super(`${code}: ${message}`);
    this.code = code;
    this.detail = message;
  }
}

class Plugin {
  constructor(input = process.stdin, output = process.stdout) {
    this.input = input;
    this.output = output;
    this.hello = null;
    this.nextId = 1;
    this.waiting = new Map();
    this.startHandlers = [];
    this.eventHandlers = new Map();
    this.uiHandlers = [];
    this.keyHandlers = new Map();
    this.queue = Promise.resolve();
  }

  onStart(handler) { this.startHandlers.push(handler); return handler; }

  on(event, handler) {
    if (!this.eventHandlers.has(event)) this.eventHandlers.set(event, []);
    this.eventHandlers.get(event).push(handler);
    return handler;
  }

  onUi(handler) { this.uiHandlers.push({ handler }); return handler; }

  onClick(target, handler, { window = null, double = false } = {}) {
    this.uiHandlers.push({ window, action: double ? "double-click" : "click", target, handler });
    return handler;
  }

  onChange(target, handler, { window = null } = {}) {
    this.uiHandlers.push({ window, action: "change", target, handler });
    return handler;
  }

  onKey(action, handler) {
    if (!this.keyHandlers.has(action)) this.keyHandlers.set(action, []);
    this.keyHandlers.get(action).push(handler);
    return handler;
  }

  send(message) {
    this.output.write(JSON.stringify(message) + "\n");
  }

  setWindow(window, elements) {
    this.send({ type: "set", window, content: { elements } });
  }

  log(text) {
    this.send({ type: "log", text: String(text) });
  }

  request(method, params = {}, { timeoutMs = 30000 } = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiting.delete(id);
        reject(new PluginError("timeout", `no answer to ${method}`));
      }, timeoutMs);
      this.waiting.set(id, { resolve, reject, timer });
      this.send({ type: "request", id, method, params });
    });
  }

  run() {
    const lines = readline.createInterface({ input: this.input, crlfDelay: Infinity });
    lines.on("line", (line) => {
      let message;
      try { message = JSON.parse(line); } catch (e) { return; }
      if (message.type === "response") {
        const waiting = this.waiting.get(message.id);
        if (!waiting) return;
        this.waiting.delete(message.id);
        clearTimeout(waiting.timer);
        if (message.error) waiting.reject(new PluginError(message.error.code, message.error.message));
        else waiting.resolve(message.result);
        return;
      }
      this.queue = this.queue.then(() => this.dispatch(message)).catch((error) => {
        process.stderr.write(`handler failed: ${error && error.stack ? error.stack : error}\n`);
      });
    });
    lines.on("close", () => {
      for (const waiting of this.waiting.values()) {
        clearTimeout(waiting.timer);
        waiting.reject(new PluginError("closed", "the app closed the connection"));
      }
      this.waiting.clear();
      this.queue.then(() => process.exit(0));
    });
  }

  async dispatch(message) {
    switch (message.type) {
      case "hello":
        this.hello = message;
        this.send({ type: "ready" });
        for (const handler of this.startHandlers) await handler(message);
        break;
      case "event":
        for (const handler of this.eventHandlers.get(message.event) || []) await handler(message.data);
        break;
      case "key":
        for (const handler of this.keyHandlers.get(message.action) || []) await handler(message);
        break;
      case "ui":
        for (const entry of this.uiHandlers) {
          if (entry.window && entry.window !== message.window) continue;
          if (entry.action && entry.action !== message.action) continue;
          if (entry.target && entry.target !== message.target) continue;
          await entry.handler(message);
        }
        break;
      default:
        break;
    }
  }
}

// -- element builders (styles: normal, title, muted, warn, new, dupe, mult) -----------------------------------
const styled = (fields, style) => (style ? Object.assign(fields, { style }) : fields);
const withId = (fields, id) => (id !== undefined && id !== null ? Object.assign(fields, { id: String(id) }) : fields);

const text = (value, style) => styled({ type: "text", text: String(value) }, style);
const column = (title, align) => (align ? { title, align } : { title });
const cell = (value, style) => styled({ text: String(value) }, style);
const row = (cells, id, style) => styled(withId({ cells }, id), style);
const table = (columns, rows, id) => withId({ type: "table", columns, rows }, id);
const item = (value, id, style) => styled(withId({ text: String(value) }, id), style);
const list = (items, id) => withId({ type: "list", items }, id);
const button = (id, label, enabled = true) => ({ type: "button", id, label, enabled });
const toggle = (id, label, value) => ({ type: "toggle", id, label, value: Boolean(value) });
const progress = (value, max, label) => (label === undefined ? { type: "progress", value, max } : { type: "progress", value, max, label });
const tab = (id, title, elements) => ({ id, title, elements });
const tabs = (tabList, id) => withId({ type: "tabs", tabs: tabList }, id);

// canvas (coordinates in points, origin top left)
const canvas = (shapes, { width = 300, height = 200, id, label } = {}) => {
  const fields = withId({ type: "canvas", width, height, shapes }, id);
  if (label !== undefined) fields.label = label;
  return fields;
};
const shape = (kind, fields, { style, fill, lineWidth } = {}) => {
  const out = Object.assign({ shape: kind }, fields);
  if (style) out.style = style;
  if (fill) out.fill = true;
  if (lineWidth !== undefined) out.lineWidth = lineWidth;
  return out;
};
const line = (x1, y1, x2, y2, options) => shape("line", { x1, y1, x2, y2 }, options);
const rect = (x, y, w, h, options) => shape("rect", { x, y, w, h }, options);
const circle = (cx, cy, r, options) => shape("circle", { cx, cy, r }, options);
const path = (points, closed = false, options) => shape("path", { points, closed }, options);
const label = (x, y, value, { style, size } = {}) => {
  const out = { shape: "text", x, y, text: String(value) };
  if (style) out.style = style;
  if (size !== undefined) out.size = size;
  return out;
};

module.exports = {
  Plugin, PluginError, text, column, cell, row, table, item, list, button, toggle, progress, tab, tabs,
  canvas, line, rect, circle, path, label,
};
