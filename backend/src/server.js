import { loadConfig } from "./config.js";
import { PlannerStore } from "./store.js";
import { createApp } from "./app.js";

let store;
try {
  const config = loadConfig();
  store = await PlannerStore.connect(config);
  await store.initialize();
  const server = createApp({ store, config }).listen(
    config.PORT,
    config.HOST,
    () =>
      console.log(`Level Up API listening on ${config.HOST}:${config.PORT}`),
  );
  server.requestTimeout = 20000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  const stop = () =>
    server.close(async () => {
      await store.client.close();
      process.exit(0);
    });
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
} catch (error) {
  console.error("Server startup failed:", error.name ?? "Error");
  if (store) await store.client.close();
  process.exitCode = 1;
}
