// scripts/dev-compose.sh keeps its secrets for the life of the stack. These tests run the real script against a fake
// `docker` that records what it was given, so no containers are needed.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { fileURLToPath } from "node:url";
import { after, before, describe, test } from "node:test";

const slashes = (path: string): string => path.replaceAll("\\", "/");
const script = slashes(fileURLToPath(new URL("../scripts/dev-compose.sh", import.meta.url)));
const hasSh = spawnSync("sh", ["-c", "exit 0"]).status === 0;

describe("dev-compose.sh", { skip: !hasSh && "no sh on this machine" }, () => {
  let dir: string;
  let fakeBin: string;
  let secretsFile: string;
  let log: string;

  before(() => {
    dir = mkdtempSync(join(tmpdir(), "dev-compose-"));
    fakeBin = join(dir, "bin");
    mkdirSync(fakeBin);
    log = slashes(join(dir, "docker.log"));
    // Records the arguments and the four secrets it was run with; `docker volume inspect` answers by FAKE_VOLUME.
    writeFileSync(
      join(fakeBin, "docker"),
      [
        "#!/bin/sh",
        'if [ "$1" = volume ]; then [ -n "${FAKE_VOLUME:-}" ]; exit $?; fi',
        'echo "$* | $POSTGRES_PASSWORD $SESSION_SECRET $TICKET_SECRET $GAME_SERVER_SECRET" >> "$FAKE_LOG"',
        'exit "${FAKE_STATUS:-0}"',
        "",
      ].join("\n"),
    );
    chmodSync(join(fakeBin, "docker"), 0o755);
    secretsFile = slashes(join(dir, "secrets", "secrets.env"));
  });
  after(() => rmSync(dir, { recursive: true, force: true }));

  const run = (args: string[], env: Record<string, string> = {}, scriptPath = script) =>
    spawnSync("sh", [slashes(scriptPath), ...args], {
      env: { ...process.env, PATH: `${fakeBin}${delimiter}${process.env.PATH}`, DEV_SECRETS_FILE: secretsFile, FAKE_LOG: log, ...env },
      encoding: "utf8",
    });
  const calls = (): string[] => (existsSync(log) ? readFileSync(log, "utf8").split("\n").filter(Boolean) : []);
  const secretsOf = (call: string): string[] => call.split(" | ")[1]!.split(" ");

  test("a second up uses the same secrets, so the database password still matches its volume", () => {
    rmSync(secretsFile, { force: true });
    rmSync(log, { force: true });
    assert.equal(run(["up", "-d"]).status, 0);
    assert.equal(run(["up", "-d"]).status, 0);
    const [first, second] = calls();
    assert.deepEqual(secretsOf(first!), secretsOf(second!));
    assert.equal(secretsOf(first!).length, 4);
    for (const value of secretsOf(first!)) assert.match(value, /^[0-9a-f]{64}$/);
    assert.equal(new Set(secretsOf(first!)).size, 4); // four different secrets
    assert.match(readFileSync(secretsFile, "utf8"), /^POSTGRES_PASSWORD=[0-9a-f]{64}$/m);
  });

  test("restart, stop and a plain down keep the secrets; down -v removes them with the volume", () => {
    assert.equal(run(["restart", "backend"]).status, 0);
    assert.equal(run(["down"]).status, 0);
    assert.ok(existsSync(secretsFile));
    assert.equal(run(["down", "-v"], { FAKE_STATUS: "1" }).status, 1); // a failed down keeps them
    assert.ok(existsSync(secretsFile));
    const gone = run(["down", "-v"]);
    assert.equal(gone.status, 0);
    assert.ok(!existsSync(secretsFile));
    assert.match(gone.stdout, /removed the development secrets/);
    // The next stack gets new secrets.
    const before = calls().length;
    assert.equal(run(["up", "-d"]).status, 0);
    assert.notDeepEqual(secretsOf(calls()[before]!), secretsOf(calls()[0]!));
  });

  test("a database volume without its secrets is refused with a clear message instead of a crash later", () => {
    rmSync(secretsFile, { force: true });
    const before = calls().length;
    const refused = run(["up", "-d"], { FAKE_VOLUME: "1" });
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /volume .* exists but its password is not in/);
    assert.match(refused.stderr, /down -v/);
    assert.equal(calls().length, before); // compose was never run
    assert.ok(!existsSync(secretsFile));
    assert.equal(run(["down", "-v"], { FAKE_VOLUME: "1" }).status, 0); // the way out works
  });

  test("a secret set in the environment wins and is not written to the file", () => {
    rmSync(secretsFile, { force: true });
    const before = calls().length;
    assert.equal(run(["up", "-d"], { SESSION_SECRET: "mine" }).status, 0);
    assert.equal(secretsOf(calls()[before]!)[1], "mine");
    assert.doesNotMatch(readFileSync(secretsFile, "utf8"), /SESSION_SECRET/);
  });

  test("the secrets file is found in the workspace scratch folder when no path is given", () => {
    const workspace = join(dir, "workspace");
    const scriptDir = join(workspace, "worktrees", "deadnight", "branch", "spikes", "backend", "scripts");
    mkdirSync(scriptDir, { recursive: true });
    mkdirSync(join(workspace, "repos"));
    mkdirSync(join(workspace, "scratch"));
    copyFileSync(script, join(scriptDir, "dev-compose.sh"));
    const result = run(["up", "-d"], { DEV_SECRETS_FILE: "" }, join(scriptDir, "dev-compose.sh"));
    assert.equal(result.status, 0, result.stderr);
    assert.ok(existsSync(join(workspace, "scratch", "deadnight-backend-dev", "secrets.env")));
  });

  test("outside a workspace, with no path given, it stops and says what to set", () => {
    const loose = join(dir, "loose", "scripts");
    mkdirSync(loose, { recursive: true });
    copyFileSync(script, join(loose, "dev-compose.sh"));
    const result = run(["up", "-d"], { DEV_SECRETS_FILE: "" }, join(loose, "dev-compose.sh"));
    assert.equal(result.status, 2);
    assert.match(result.stderr, /DEV_SECRETS_FILE/);
  });
});
