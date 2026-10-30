import { createHash } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { transition } from "./domain.js";
import { ApiError } from "./errors.js";
import { parse, syncSchema } from "./schema.js";

initializeApp();

const firestore = getFirestore();
const maxPlannerDocumentBytes = 900_000;
const privateCollections = [
  "habits",
  "categories",
  "notes",
  "focus",
  "todos",
  "todoTags",
];

const canonical = (value) =>
  Array.isArray(value)
    ? value.map(canonical)
    : value && typeof value === "object"
      ? Object.fromEntries(
          Object.keys(value)
            .sort()
            .map((key) => [key, canonical(value[key])]),
        )
      : value;

const requestHash = (input) =>
  createHash("sha256")
    .update(JSON.stringify(canonical(input)))
    .digest("hex");

const encodedSize = (value) => Buffer.byteLength(JSON.stringify(value), "utf8");

function asSnapshot(value) {
  if (!value) return { revision: 0, state: null, settings: {} };
  const revision = value.revision;
  if (!Number.isInteger(revision) || revision < 0) {
    throw new HttpsError("failed-precondition", "Cloud state is invalid.");
  }
  return {
    revision,
    state: value.state ?? null,
    settings: value.settings ?? {},
    timeZone: value.timeZone,
    serverTime:
      value.updatedAt && typeof value.updatedAt.toDate === "function"
        ? value.updatedAt.toDate().toISOString()
        : undefined,
  };
}

function conflict(snapshot) {
  return new HttpsError(
    "aborted",
    "Cloud data changed. Review the retained local changes before retrying.",
    { snapshot },
  );
}

function plannerError(error) {
  if (error instanceof HttpsError) return error;
  if (error instanceof ApiError) {
    return new HttpsError(
      error.code === "history_conflict" ? "failed-precondition" : "invalid-argument",
      "The planner change was rejected.",
      { code: error.code },
    );
  }
  return new HttpsError("internal", "The planner update could not be confirmed.");
}

function privateError(error) {
  if (error instanceof HttpsError) return error;
  return new HttpsError("invalid-argument", "The private data update is invalid.");
}

function privateData(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Private data must be an object.");
  }
  const keys = Object.keys(value).sort();
  if (
    keys.length !== privateCollections.length ||
    keys.some((key, index) => key !== [...privateCollections].sort()[index])
  ) {
    throw new HttpsError("invalid-argument", "Unexpected private data collection.");
  }
  for (const key of privateCollections) {
    const collection = value[key];
    if (!collection || typeof collection !== "object" || Array.isArray(collection)) {
      throw new HttpsError("invalid-argument", "Private collections must be maps.");
    }
  }
  if (encodedSize(value) > maxPlannerDocumentBytes) {
    throw new HttpsError("resource-exhausted", "Private data is too large.");
  }
  return value;
}

export const syncPlannerState = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to synchronize data.");
    }
    let input;
    try {
      input = parse(syncSchema, request.data);
    } catch (error) {
      throw plannerError(error);
    }
    if (encodedSize(input) > maxPlannerDocumentBytes) {
      throw new HttpsError(
        "resource-exhausted",
        "Planner data is too large for this migration path.",
      );
    }

    const ownerId = request.auth.uid;
    const stateRef = firestore.doc(`users/${ownerId}/planner/state`);
    const mutationRef = stateRef.collection("mutations").doc(input.mutationId);
    const hash = requestHash(input);

    try {
      return await firestore.runTransaction(async (transaction) => {
        const [stateDocument, mutationDocument] = await Promise.all([
          transaction.get(stateRef),
          transaction.get(mutationRef),
        ]);
        const current = asSnapshot(stateDocument.data());

        if (mutationDocument.exists) {
          const accepted = mutationDocument.data();
          if (accepted.requestHash !== hash) {
            throw new HttpsError(
              "already-exists",
              "This mutation identifier was already used.",
              { code: "mutation_reused" },
            );
          }
          if (accepted.revision !== current.revision) throw conflict(current);
          return current;
        }

        if (current.revision !== input.baseRevision) throw conflict(current);
        const nextState = transition(current.state, input.state, {
          now: new Date(),
          timeZone: input.timeZone,
        });
        const revision = current.revision + 1;
        const response = {
          revision,
          state: nextState,
          settings: input.settings,
          timeZone: input.timeZone,
          serverTime: new Date().toISOString(),
        };
        if (encodedSize(response) > maxPlannerDocumentBytes) {
          throw new HttpsError(
            "resource-exhausted",
            "Planner data is too large for this migration path.",
          );
        }
        transaction.set(stateRef, {
          schemaVersion: 1,
          revision,
          state: nextState,
          settings: input.settings,
          timeZone: input.timeZone,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(mutationRef, {
          requestHash: hash,
          revision,
          createdAt: FieldValue.serverTimestamp(),
        });
        const email = request.auth.token.email;
        transaction.set(
          firestore.doc(`users/${ownerId}`),
          {
            schemaVersion: 1,
            ...(typeof email === "string" ? { email } : {}),
            lastPlannerSyncAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return response;
      });
    } catch (error) {
      throw plannerError(error);
    }
  },
);

/// Account-owned habit, task, focus and note records. It deliberately excludes
/// device settings and planner state; the latter is validated by syncPlannerState.
export const syncPrivateData = onCall(
  {
    region: "us-central1",
    enforceAppCheck: true,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to synchronize data.");
    }
    const input = request.data;
    try {
      if (!input || typeof input !== "object" || Array.isArray(input)) {
        throw new HttpsError("invalid-argument", "Invalid private data request.");
      }
      if (
        typeof input.mutationId !== "string" ||
        input.mutationId.length < 8 ||
        input.mutationId.length > 128 ||
        !Number.isInteger(input.baseRevision) ||
        input.baseRevision < 0
      ) {
        throw new HttpsError("invalid-argument", "Invalid private data revision.");
      }
      input.data = privateData(input.data);
    } catch (error) {
      throw privateError(error);
    }

    const ownerId = request.auth.uid;
    const stateRef = firestore.doc(`users/${ownerId}/private/state`);
    const mutationRef = stateRef.collection("mutations").doc(input.mutationId);
    const hash = requestHash(input);
    try {
      return await firestore.runTransaction(async (transaction) => {
        const [stateDocument, mutationDocument] = await Promise.all([
          transaction.get(stateRef),
          transaction.get(mutationRef),
        ]);
        const current = stateDocument.data() ?? { revision: 0, data: null };
        if (!Number.isInteger(current.revision) || current.revision < 0) {
          throw new HttpsError("failed-precondition", "Private data is invalid.");
        }
        if (mutationDocument.exists) {
          const accepted = mutationDocument.data();
          if (accepted.requestHash !== hash) {
            throw new HttpsError("already-exists", "This mutation identifier was already used.");
          }
          if (accepted.revision !== current.revision) {
            throw new HttpsError("aborted", "Private data changed.", {
              revision: current.revision,
              data: current.data,
            });
          }
          return { revision: current.revision, data: current.data };
        }
        if (current.revision !== input.baseRevision) {
          throw new HttpsError("aborted", "Private data changed.", {
            revision: current.revision,
            data: current.data,
          });
        }
        const revision = current.revision + 1;
        transaction.set(stateRef, {
          schemaVersion: 1,
          revision,
          data: input.data,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(mutationRef, {
          requestHash: hash,
          revision,
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.set(
          firestore.doc(`users/${ownerId}`),
          { schemaVersion: 1, lastPrivateSyncAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
        return { revision, data: input.data };
      });
    } catch (error) {
      throw privateError(error);
    }
  },
);
