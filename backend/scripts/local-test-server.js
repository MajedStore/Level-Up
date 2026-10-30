// Local integration fixture only. Starts a real temporary MongoDB replica set;
// it is not an Atlas deployment and must not be exposed to the public internet.
import { randomBytes } from "node:crypto";
import { MongoMemoryReplSet } from "mongodb-memory-server";
import { MongoClient } from "mongodb";
import { PlannerStore } from "../src/store.js";
import { createApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";

let replica,
  client,
  server,
  closing = false;
async function close() {
  if (closing) return;
  closing = true;
  if (server) await new Promise((resolve) => server.close(resolve));
  await client?.close();
  await replica?.stop();
}
try {
  const port = Number(process.env.TEST_API_PORT ?? 4317);
  if (!Number.isInteger(port) || port < 1024 || port > 65535)
    throw new Error("Invalid test port.");
  replica = await MongoMemoryReplSet.create({
    binary: { version: "8.0.17" },
    replSet: { count: 1, storageEngine: "wiredTiger" },
  });
  client = new MongoClient(replica.getUri(), {
    serverSelectionTimeoutMS: 5000,
  });
  await client.connect();
  const store = new PlannerStore(client, "level_up_flutter_integration");
  await store.initialize();
  const config = loadConfig({
    NODE_ENV: "test",
    MONGODB_URI: replica.getUri(),
    JWT_SECRET: randomBytes(48).toString("base64url"),
  });
  const app = createApp({ store, config, hashCost: 8, authLimit: 200 });
  server = app.listen(port, "127.0.0.1", () =>
    console.log(`TEST_API_READY http://127.0.0.1:${port}`),
  );
  server.requestTimeout = 20000;
  server.headersTimeout = 10000;
  process.on("SIGINT", () => close().then(() => process.exit(0)));
  process.on("SIGTERM", () => close().then(() => process.exit(0)));
  process.on("uncaughtException", async () => {
    console.error("Local integration fixture failed.");
    await close();
    process.exit(1);
  });
} catch (error) {
  console.error(
    "Local integration fixture startup failed:",
    error.name ?? "Error",
  );
  await close();
  process.exitCode = 1;
}
