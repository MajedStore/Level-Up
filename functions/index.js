import { createHash } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { transition } from "level-up-api/src/domain.js";
import { ApiError } from "level-up-api/src/errors.js";
import { parse, syncSchema } from "level-up-api/src/schema.js";

initializeApp();

const firestore = getFirestore();
const maxPlannerDocumentBytes = 900_000;

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
