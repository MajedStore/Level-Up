import { loadConfig } from "../src/config.js";
import { PlannerStore } from "../src/store.js";
let store;
try {
  store = await PlannerStore.connect(loadConfig());
  await store.initialize({ applyValidators: true });
  console.log(
    "Additive database initialization completed. Existing records retained.",
  );
} catch (error) {
  console.error("Database initialization failed:", error.name ?? "Error");
  process.exitCode = 1;
} finally {
  await store?.client.close();
}
