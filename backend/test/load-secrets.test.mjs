import assert from "node:assert/strict";
import test from "node:test";

import { loadSecrets } from "../load-secrets.mjs";

const SECRET_ENV = { DB_SECRET_ID: "placeholder-db", JWT_SECRET_ID: "placeholder-jwt" };

test("loads DB_PASSWORD and AUTH_JWT_SECRET from the secrets", async () => {
  const env = { ...SECRET_ENV };
  const secrets = {
    "placeholder-db": JSON.stringify({ password: "db-placeholder" }),
    "placeholder-jwt": JSON.stringify({ AUTH_JWT_SECRET: "jwt-placeholder" }),
  };

  await loadSecrets(env, async (id) => secrets[id]);

  assert.equal(env.DB_PASSWORD, "db-placeholder");
  assert.equal(env.AUTH_JWT_SECRET, "jwt-placeholder");
});

test("does nothing when no secret id is defined", async () => {
  const env = {};
  const read = async () => assert.fail("must not read secrets");

  assert.deepEqual(await loadSecrets(env, read), []);
  assert.deepEqual(env, {});
});

test("fails when the expected field is missing or empty, without leaking values", async () => {
  const env = { DB_SECRET_ID: "placeholder-db" };

  await assert.rejects(
    loadSecrets(env, async () => JSON.stringify({ username: "leaky-value" })),
    (error) => /"password"/.test(error.message) && !error.message.includes("leaky-value"),
  );
  await assert.rejects(loadSecrets(env, async () => JSON.stringify({ password: "  " })), /"password"/);
});

test("fails when reading the secret fails", async () => {
  const env = { JWT_SECRET_ID: "placeholder-jwt" };

  await assert.rejects(
    loadSecrets(env, async () => {
      throw Object.assign(new Error("sensitive detail"), { name: "AccessDeniedException" });
    }),
    (error) => /JWT_SECRET_ID/.test(error.message) && !error.message.includes("sensitive detail"),
  );
  assert.equal(env.AUTH_JWT_SECRET, undefined);
});
