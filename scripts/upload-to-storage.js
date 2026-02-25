#!/usr/bin/env node
// Upload files to Firebase Storage using firebase-tools credentials
const fs = require("fs");
const path = require("path");
const https = require("https");
const os = require("os");

const BUCKET = "whisper-f6336.firebasestorage.app";

// Google OAuth client used by firebase-tools
const CLIENT_ID =
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";

function getConfig() {
  const configPath = path.join(
    os.homedir(),
    ".config",
    "configstore",
    "firebase-tools.json"
  );
  return JSON.parse(fs.readFileSync(configPath, "utf8"));
}

function saveConfig(config) {
  const configPath = path.join(
    os.homedir(),
    ".config",
    "configstore",
    "firebase-tools.json"
  );
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

function refreshAccessToken(refreshToken) {
  return new Promise((resolve, reject) => {
    const postData = new URLSearchParams({
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    }).toString();

    const options = {
      hostname: "oauth2.googleapis.com",
      path: "/token",
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": Buffer.byteLength(postData),
      },
    };

    const req = https.request(options, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => {
        if (res.statusCode === 200) {
          resolve(JSON.parse(body));
        } else {
          reject(new Error(`Token refresh failed (${res.statusCode}): ${body}`));
        }
      });
    });

    req.on("error", reject);
    req.write(postData);
    req.end();
  });
}

async function getAccessToken() {
  const config = getConfig();

  if (!config.tokens?.refresh_token) {
    throw new Error("No refresh token found. Run 'firebase login' first.");
  }

  // Always refresh to get a valid token
  const result = await refreshAccessToken(config.tokens.refresh_token);

  // Save the new access token
  config.tokens.access_token = result.access_token;
  saveConfig(config);

  return result.access_token;
}

function upload(filePath, storagePath, contentType, accessToken) {
  return new Promise((resolve, reject) => {
    const fileData = fs.readFileSync(filePath);
    const encodedPath = encodeURIComponent(storagePath);
    const url = `/upload/storage/v1/b/${BUCKET}/o?uploadType=media&name=${encodedPath}`;

    const options = {
      hostname: "storage.googleapis.com",
      path: url,
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": contentType,
        "Content-Length": fileData.length,
      },
    };

    const req = https.request(options, (res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(body));
        } else {
          reject(new Error(`Upload failed (${res.statusCode}): ${body}`));
        }
      });
    });

    req.on("error", reject);
    req.write(fileData);
    req.end();
  });
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 3) {
    console.error(
      "Usage: upload-to-storage.js <local-file> <storage-path> <content-type>"
    );
    process.exit(1);
  }

  const [localFile, storagePath, contentType] = args;

  if (!fs.existsSync(localFile)) {
    console.error(`File not found: ${localFile}`);
    process.exit(1);
  }

  const size = (fs.statSync(localFile).size / 1024 / 1024).toFixed(1);
  console.log(
    `Uploading ${path.basename(localFile)} (${size} MB) → ${storagePath}`
  );

  const accessToken = await getAccessToken();
  const result = await upload(localFile, storagePath, contentType, accessToken);
  const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(storagePath)}?alt=media`;
  console.log(`Done: ${publicUrl}`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
