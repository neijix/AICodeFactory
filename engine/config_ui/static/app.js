// The settings page: renders /api/state, sends each change to /api/<action>, re-renders the
// state it gets back. Every text from the server goes through textContent, never innerHTML.
"use strict";

const token = document.querySelector('meta[name="aicf-token"]').content;
let state = null;
let selected = "";
let checks = null;   // the projects check: null, {loading: true}, {error}, or {projects, counts}

const $ = (id) => document.getElementById(id);

function el(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs || {})) {
    if (name === "on") Object.entries(value).forEach(([type, fn]) => node.addEventListener(type, fn));
    else if (name === "text") node.textContent = value;
    else if (value !== false && value !== null && value !== undefined) node.setAttribute(name, value === true ? "" : value);
  }
  children.flat().forEach((child) => node.append(child instanceof Node ? child : String(child)));
  return node;
}

async function call(method, path, body) {
  const response = await fetch(path, {
    method,
    headers: { "X-AICF-Token": token, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({ error: `HTTP ${response.status}` }));
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
  return data;
}

function toast(text, bad) {
  const box = $("toast");
  box.textContent = text;
  box.className = bad ? "show bad" : "show";
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { box.className = ""; }, bad ? 9000 : 3500);
}

async function act(action, body, done) {
  try {
    const data = await call("POST", `/api/${action}`, body);
    if (data.state) { state = data.state; render(); }
    toast(done || "Saved.");
    return data;
  } catch (error) {
    toast(error.message, true);
    return null;
  }
}

function pathKey(path) {
  return String(path || "").replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

function samePath(a, b) {
  return pathKey(a) === pathKey(b);
}

function nameOf(env) {
  return (env.raw && env.raw.label) || env.root;
}

function current() {
  return state.environments.find((env) => env.root === selected) || state.environments[0];
}

function render() {
  $("brain").textContent = `Brain: ${state.brain}`;
  if (!state.environments.some((env) => env.root === selected)) selected = state.environments[0]?.root || "";
  renderRoots();
  renderPersonal();
  renderDetail();
  const folders = $("scan-form").elements.folders;
  if (!folders.value) folders.value = state.scan_folders.join("\n");
}

function badge(text, kind) {
  return el("span", { class: `badge ${kind || ""}`, text });
}

function renderRoots() {
  const cards = state.environments.map((env) => el("article", { class: env.root === selected ? "card picked" : "card" },
    el("div", { class: "card-head" },
      el("strong", { text: env.root }),
      badge(env.kind, env.kind === "work" ? "warn" : ""),
      env.code_root ? badge("environment", "ok") : badge("not set up yet", "warn"),
      env.brain_root ? badge("AICodeFactory's root") : ""),
    el("p", { class: "muted", text: `${env.label || "no label"} · ${env.projects} git project(s)` }),
    env.code_root ? skillFolders(env) : "",
    env.code_root ? projectChecks(env) : "",
    el("div", { class: "row" },
      el("button", { type: "button", class: "ghost", on: { click: () => { selected = env.root; render(); $("detail-title").scrollIntoView(); } } }, "Skills and steps"),
      env.code_root ? "" : el("button", { type: "button", on: { click: () => act("root-add", { path: env.root, label: (env.raw && env.raw.label) || "", kind: env.kind }, "Set up.") } }, "Set it up"),
      env.forgettable ? el("button", { type: "button", class: "ghost", on: { click: () => forget(env.root) } }, "Forget") : "")));
  $("root-list").replaceChildren(...cards);
}

// The environment's own skills folders (`overlays` in its environment.json), editable in place.
function skillFolders(env) {
  const input = el("input", { name: "path", placeholder: "a folder whose sub-folders hold a SKILL.md, or a repo with skills/", required: true, "aria-label": `Skills folder for ${env.root}` });
  const add = async (event) => {
    event.preventDefault();
    const path = input.value.trim();
    if (path && await setExtras(env, [...env.overlays, path], `Skills folder added to ${nameOf(env)}.`)) input.value = "";
  };
  return el("div", { class: "box" },
    el("h3", { text: "Skills folders" }),
    el("p", { class: "muted small", text: env.brain_root
      ? "Installed for every environment: personal or work by where each folder sits."
      : "Installed on this machine, on only in this environment's projects (off in the others unless one turns them on)." }),
    el("ul", { class: "list" }, env.overlays.length ? env.overlays.map((folder) => el("li", {},
      el("code", { text: folder }),
      el("button", { type: "button", class: "ghost small", on: { click: () => setExtras(env, env.overlays.filter((f) => f !== folder), "Removed.") } }, "Remove")))
      : [el("li", { class: "muted", text: "None yet." })]),
    el("form", { class: "row", on: { submit: add } }, el("label", { class: "grow" }, "Folder", input), el("button", { type: "submit" }, "Add folder")));
}

// What the last projects check found in this environment.
function projectChecks(env) {
  const box = el("div", { class: "box" }, el("h3", { text: "Projects" }));
  if (!checks || checks.loading) {
    box.append(el("p", { class: "muted small", text: checks ? "Checking every project (aicf doctor)…" : "Not checked yet." }));
    return box;
  }
  if (checks.error) {
    box.append(el("p", { class: "error small", text: checks.error }));
    return box;
  }
  const rows = checks.projects[pathKey(env.root)] || [];
  if (!rows.length) {
    box.append(el("p", { class: "muted small", text: "No git project directly inside this folder." }));
    return box;
  }
  const ready = rows.filter((row) => row.status === "ok");
  const todo = rows.filter((row) => row.status !== "ok");
  box.append(el("p", {}, todo.length ? badge(`${todo.length} need work`, "warn") : badge("all set up", "ok"),
    ` ${ready.length} of ${rows.length} set up for AICodeFactory.`));
  if (todo.length) {
    box.append(el("table", { class: "grid" },
      el("thead", {}, el("tr", {}, el("th", { text: "Project" }), el("th", { text: "State" }), el("th", { text: "To do" }))),
      el("tbody", {}, todo.map((row) => el("tr", {},
        el("td", {}, el("code", { text: row.name })),
        el("td", {}, badge(row.status_label, "warn")),
        el("td", {}, el("code", { text: row.action })))))));
  }
  if (ready.length) box.append(el("p", { class: "muted small", text: `Set up: ${ready.map((row) => row.name).join(", ")}` }));
  return box;
}

async function checkProjects() {
  const button = $("check-projects");
  button.disabled = true;
  checks = { loading: true };
  renderRoots();
  try {
    const data = await call("POST", "/api/projects", {});
    const projects = {};
    for (const [root, rows] of Object.entries(data.projects)) projects[pathKey(root)] = rows;
    checks = { projects, counts: data.counts };
  } catch (error) {
    checks = { error: error.message };
  }
  button.disabled = false;
  renderRoots();
}

function forget(root) {
  if (!confirm(`Stop listing ${root} here? Its .ai-root folder stays; delete it by hand to stop AICodeFactory there.`)) return;
  act("root-forget", { path: root }, "Forgotten.");
}

function renderPersonal() {
  const p = state.personal;
  const status = $("personal-status");
  if (!p.path) {
    status.replaceChildren(badge("none", "warn"), " No personal overlay on this machine.");
  } else {
    const how = { variable: "from AI_TEMPLATE_OVERLAY_DIR", marker: "from ~/.ai-template-overlay-dir", sibling: "found next to AICodeFactory" }[p.source] || "";
    status.replaceChildren(el("strong", { text: p.path }), ` (${how}) — `,
      p.skills_dir ? `${p.skills.length} skill(s): ${p.skills.join(", ") || "none"}` : "no skills/ folder yet");
  }
  const form = $("factory");
  form.hidden = !p.path;
  form.elements.identity.value = state.identity || "";
  form.elements.taste.value = state.taste || "";
}

function renderDetail() {
  const env = current();
  if (!env) return;
  $("root-pick").replaceChildren(...state.environments.map((item) =>
    el("option", { value: item.root, selected: item.root === env.root, text: `${item.label || item.kind} — ${item.root}` })));
  $("root-error").hidden = !env.error;
  $("root-error").textContent = env.error || "";
  renderSkills(env);
  renderSteps(env);
}

function setExtras(env, overlays, done) {
  return act("environment", { root: env.root, values: { overlays } }, done);
}

function renderSkills(env) {
  const rows = env.skills.map((skill) => el("tr", {},
    el("td", { text: skill.name }),
    el("td", { text: skill.source }),
    el("td", {}, skill.enabled ? badge("on", "ok") : badge("off")),
    el("td", {}, el("select", {
      "aria-label": `Setting for ${skill.name}`,
      on: { change: (event) => act("skill", { root: env.root, name: skill.name, state: event.target.value }) },
    }, ["default", "on", "off"].map((value) => el("option", { value, selected: skill.state === value, text: value }))))));
  $("skill-rows").replaceChildren(...(rows.length ? rows : [el("tr", {}, el("td", { colspan: 4, class: "muted", text: "No skill found." }))]));
}

function renderSteps(env) {
  const raw = env.raw || {};
  const rows = state.steps.map((step) => {
    const now = env.workflow[step];
    const field = (name) => raw[`workflow.${step}.${name}`] || "";
    return el("tr", {},
      el("td", { text: step }),
      el("td", {}, el("select", { name: `workflow.${step}.agent`, "aria-label": `${step} agent` },
        el("option", { value: "", text: `inherit (${now.agent || "none"})` }),
        state.agents.map((agent) => el("option", { value: agent, selected: field("agent") === agent, text: agent })))),
      el("td", {}, el("input", { name: `workflow.${step}.model`, value: field("model"), placeholder: now.model, size: 10, "aria-label": `${step} model` })),
      el("td", {}, el("input", { name: `workflow.${step}.effort`, value: field("effort"), placeholder: now.effort, size: 8, "aria-label": `${step} effort` })));
  });
  $("step-rows").replaceChildren(...rows);
}

function formValues(form) {
  return Object.fromEntries([...form.elements].filter((item) => item.name).map((item) => [item.name, item.value.trim()]));
}

function renderScan(result) {
  $("scan-note").textContent = `${result.candidates.length} folder(s) of skills, ${result.visited} folder(s) looked at` +
    (result.truncated ? " — stopped early (time or size limit): scan a narrower folder for the rest." : ".");
  const env = current();
  $("scan-results").replaceChildren(...result.candidates.map((found) => el("article", { class: "card" },
    el("div", { class: "card-head" }, el("strong", { text: found.path }), found.used ? badge(`used: ${found.used}`, "ok") : badge("new")),
    el("p", { class: "muted", text: `${found.skills.length} skill(s): ${found.skills.join(", ")}` }),
    found.used ? "" : el("div", { class: "row" },
      env ? el("button", { type: "button", on: { click: () => setExtras(env, [...env.overlays, found.path], `Added to ${nameOf(env)}.`) } },
        `Add as a skills folder of ${nameOf(env)}`) : "",
      found.overlay ? el("button", { type: "button", class: "ghost", on: { click: () => act("overlay-set", { path: found.overlay }, "Personal overlay set.") } },
        `Use ${found.overlay} as my personal overlay`) : ""))));
}

function wire() {
  $("root-add").addEventListener("submit", async (event) => {
    event.preventDefault();
    const data = await act("root-add", formValues(event.target), "Environment added.");
    if (!data) return;
    event.target.reset();
    const added = state.environments.find((env) => samePath(env.root, data.added));
    if (added) { selected = added.root; render(); }
  });
  $("personal-set").addEventListener("submit", (event) => {
    event.preventDefault();
    act("overlay-set", formValues(event.target), "Personal overlay set. Its skills install at the next session start.");
  });
  $("personal-clear").addEventListener("click", () => {
    if (confirm("Forget the personal overlay on this machine? The folder itself is not touched.")) act("overlay-clear", {}, "Forgotten.");
  });
  $("factory").addEventListener("submit", (event) => {
    event.preventDefault();
    act("factory", { values: formValues(event.target) });
  });
  $("root-pick").addEventListener("change", (event) => { selected = event.target.value; render(); });
  $("check-projects").addEventListener("click", checkProjects);
  $("workflow").addEventListener("submit", (event) => {
    event.preventDefault();
    act("environment", { root: current().root, values: formValues(event.target) });
  });
  $("scan-form").addEventListener("submit", scanNow);
  $("close").addEventListener("click", async () => {
    await call("POST", "/api/shutdown", {}).catch(() => null);
    document.body.replaceChildren(el("main", {}, el("p", { text: "The settings server stopped. Run aicf config to open it again." })));
  });
}

async function scanNow(event) {
  event.preventDefault();
  const folders = event.target.elements.folders.value.split("\n").map((line) => line.trim()).filter(Boolean);
  const button = $("scan-button");
  button.disabled = true;
  $("scan-note").textContent = "Scanning…";
  const data = await act("scan", { folders }, "Scan done.");
  button.disabled = false;
  if (data) renderScan(data);
  else $("scan-note").textContent = "";
}

async function start() {
  wire();
  try {
    state = await call("GET", "/api/state");
    render();
    checkProjects();
  } catch (error) {
    toast(error.message, true);
  }
}

start();
