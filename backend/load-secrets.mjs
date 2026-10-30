// Preload executed with `node --import ./load-secrets.mjs` before config/env.js
// is evaluated. It fills DB_PASSWORD and AUTH_JWT_SECRET from AWS Secrets
// Manager when DB_SECRET_ID and/or JWT_SECRET_ID are defined. Without them
// (local development) it does nothing and the AWS SDK is never loaded.

const SECRETS = [
  { idVariable: "DB_SECRET_ID", field: "password", target: "DB_PASSWORD" },
  { idVariable: "JWT_SECRET_ID", field: "AUTH_JWT_SECRET", target: "AUTH_JWT_SECRET" },
];

const hasValue = (value) => typeof value === "string" && value.trim() !== "";

const extractField = (secretString, { idVariable, field }) => {
  let parsed;

  try {
    parsed = JSON.parse(secretString);
  } catch {
    throw new Error(`Secret referenced by ${idVariable} is not valid JSON`);
  }

  const value = parsed?.[field];

  if (!hasValue(value)) {
    throw new Error(`Secret referenced by ${idVariable} must contain a non-empty "${field}" field`);
  }

  return value;
};

const createSecretsManagerReader = async (region) => {
  const { SecretsManagerClient, GetSecretValueCommand } = await import(
    "@aws-sdk/client-secrets-manager"
  );
  const client = new SecretsManagerClient({ region });

  return async (secretId) => {
    const response = await client.send(new GetSecretValueCommand({ SecretId: secretId }));
    return response.SecretString;
  };
};

// `readSecret` can be injected (tests); otherwise the AWS SDK is imported lazily.
export const loadSecrets = async (env = process.env, readSecret) => {
  const pending = SECRETS.filter(({ idVariable }) => hasValue(env[idVariable]));

  if (pending.length === 0) {
    return [];
  }

  const read = readSecret ?? (await createSecretsManagerReader(env.AWS_REGION || "us-east-1"));
  const loaded = [];

  for (const secret of pending) {
    let secretString;

    try {
      secretString = await read(env[secret.idVariable].trim());
    } catch (error) {
      throw new Error(
        `Could not read secret referenced by ${secret.idVariable} (${error?.name ?? "Error"})`,
      );
    }

    if (!hasValue(secretString)) {
      throw new Error(`Secret referenced by ${secret.idVariable} has no SecretString`);
    }

    env[secret.target] = extractField(secretString, secret);
    loaded.push(secret.target);
  }

  console.log(`Secrets loaded from AWS Secrets Manager: ${loaded.join(", ")}`);
  return loaded;
};

await loadSecrets();
