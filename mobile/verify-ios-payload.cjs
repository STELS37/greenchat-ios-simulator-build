#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const root = __dirname;
const sourcePath = path.join(root, "SOURCE_SHA.txt");
const payloadRoot = path.join(root, "ios", "App", "App", "public");
const profilePath = path.join(payloadRoot, ".gc-build-profile.json");

function fail(message) {
  console.error("GreenChat iOS payload verification: " + message);
  process.exit(1);
}

if (!fs.existsSync(sourcePath)) fail("SOURCE_SHA.txt is missing");
if (!fs.existsSync(profilePath)) fail("public/.gc-build-profile.json is missing");

const sourceSha = fs.readFileSync(sourcePath, "utf8").trim();
if (!/^[0-9a-f]{40}$/.test(sourceSha)) fail("SOURCE_SHA.txt is not a full Git SHA");

let profile;
try {
  profile = JSON.parse(fs.readFileSync(profilePath, "utf8"));
} catch (error) {
  fail("build profile is invalid JSON: " + error.message);
}

if (profile.build_id !== sourceSha) {
  fail("payload/source mismatch: profile=" + profile.build_id + " source=" + sourceSha);
}
if (!Array.isArray(profile.files) || profile.files.length === 0) {
  fail("build profile has no file manifest");
}

let totalBytes = 0;
for (const entry of profile.files) {
  if (!entry || typeof entry.path !== "string" || !/^[0-9a-f]{64}$/.test(entry.sha256)) {
    fail("invalid manifest entry");
  }
  const fullPath = path.resolve(payloadRoot, entry.path);
  if (!fullPath.startsWith(payloadRoot + path.sep)) fail("path escapes the payload: " + entry.path);

  let stat;
  try {
    stat = fs.statSync(fullPath);
  } catch {
    fail("missing payload file: " + entry.path);
  }
  if (!stat.isFile()) fail("payload entry is not a regular file: " + entry.path);
  if (stat.size !== entry.size) fail("size mismatch: " + entry.path);

  const digest = crypto.createHash("sha256").update(fs.readFileSync(fullPath)).digest("hex");
  if (digest !== entry.sha256) fail("SHA-256 mismatch: " + entry.path);
  totalBytes += stat.size;
}

for (const required of ["index.html", "gc-preboot.js", "gc-bridge.js", "gc-store-update.js", "gc-ios-liquid-glass.css"]) {
  if (!fs.existsSync(path.join(payloadRoot, required))) fail("required iOS web asset is missing: " + required);
}

console.log("GreenChat iOS payload: PASS");
console.log("Source SHA: " + sourceSha);
console.log("Files verified: " + profile.files.length);
const html = fs.readFileSync(path.join(payloadRoot, "index.html"), "utf8");
const entry = html.match(/name="gc-app-entry" content="([^"]+)"/);
const stylesheet = html.match(/id="gc-app-style" rel="stylesheet" href="([^"]+)"/);
if (!entry || !stylesheet) fail("app entrypoint or primary stylesheet reference is missing");
for (const asset of [entry[1], stylesheet[1]]) {
  const relative = asset.startsWith("/") ? asset.slice(1) : asset;
  if (!fs.existsSync(path.join(payloadRoot, relative))) fail("referenced app asset is missing: " + relative);
}
console.log("Main app entrypoint: " + entry[1]);
console.log("Main stylesheet: " + stylesheet[1]);
console.log("Bytes verified: " + totalBytes);
